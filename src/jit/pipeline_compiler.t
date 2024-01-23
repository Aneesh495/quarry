-- Quarry holistic pipeline fusion JIT compiler
-- Assembles relational operators into single-loop compiled LLVM native kernels.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local builder = require("src.jit/builder")

local DataChunk = chunk.DataChunk

local pipeline_compiler = {}

-- Compiles a fused filter-and-aggregation kernel
-- Evaluates: for each row: if pred(v) then sum = sum + proj(v); count = count + 1
function pipeline_compiler.compile_filter_sum(filter_col_idx, filter_op, threshold, val_col_idx)
    local v_filt = symbol(int64, "filt_val")
    local v_val = symbol(int64, "proj_val")

    local pred
    if filter_op == ">" then
        pred = `([v_filt] > threshold)
    elseif filter_op == "<" then
        pred = `([v_filt] < threshold)
    elseif filter_op == ">=" then
        pred = `([v_filt] >= threshold)
    elseif filter_op == "<=" then
        pred = `([v_filt] <= threshold)
    elseif filter_op == "!=" then
        pred = `([v_filt] ~= threshold)
    else
        pred = `([v_filt] == threshold)
    end

    local terra fused_kernel(c: &DataChunk, out_count: &uint64, out_sum: &int64)
        var col_f = c:get_column(filter_col_idx)
        var col_v = c:get_column(val_col_idx)
        var n = c.num_rows

        var total_cnt : uint64 = 0
        var total_sum : int64 = 0

        var raw_f = [&int64](col_f.raw_data)
        var raw_v = [&int64](col_v.raw_data)

        if c.has_selection then
            for i = 0, n do
                var phys_idx = c.selection_vector[i]
                var [v_filt] = raw_f[phys_idx]
                var [v_val] = raw_v[phys_idx]
                if [pred] then
                    total_cnt = total_cnt + 1
                    total_sum = total_sum + [v_val]
                end
            end
        else
            for i = 0, n do
                var [v_filt] = raw_f[i]
                var [v_val] = raw_v[i]
                if [pred] then
                    total_cnt = total_cnt + 1
                    total_sum = total_sum + [v_val]
                end
            end
        end

        @out_count = total_cnt
        @out_sum = total_sum
    end

    return fused_kernel
end

-- Compiles a fused filter-and-project kernel that writes to an output DataChunk
function pipeline_compiler.compile_filter_project(filter_col_idx, filter_op, threshold, scale_factor)
    local v_filt = symbol(int64, "filt_val")
    local v_score = symbol(int64, "score_val")

    local pred
    if filter_op == ">" then
        pred = `([v_filt] > threshold)
    elseif filter_op == "<" then
        pred = `([v_filt] < threshold)
    else
        pred = `([v_filt] == threshold)
    end

    local terra fused_fp_kernel(in_c: &DataChunk, out_c: &DataChunk) : uint32
        var col_f = in_c:get_column(filter_col_idx)
        var n = in_c.num_rows
        var raw_f = [&int64](col_f.raw_data)

        var matched : uint32 = 0
        var out_col0 = out_c:get_column(0)
        var out_col1 = out_c:get_column(1)

        for i = 0, n do
            var phys_idx = in_c:get_row_index(i)
            var [v_filt] = raw_f[phys_idx]

            if [pred] then
                out_col0:set_i64(matched, [v_filt])
                var scaled = [double]([v_filt]) * scale_factor
                out_col1:set_f64(matched, scaled)
                matched = matched + 1
            end
        end

        out_c.num_rows = matched
        out_c.has_selection = false
        return matched
    end

    return fused_fp_kernel
end

return pipeline_compiler
