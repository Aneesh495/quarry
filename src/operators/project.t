-- Quarry physical vectorized projection operator
-- Evaluates scalar expressions and populates output chunk buffers.

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk

local project = {}

struct ProjectionMapping {
    source_col_idx: uint32,
    dest_col_idx: uint32,
    is_scale_mul: bool,
    scale_factor: double
}

struct PhysicalProject {
    num_projections: uint32,
    mappings: ProjectionMapping[32]
}

terra PhysicalProject:init(num_proj: uint32)
    self.num_projections = num_proj
    for i = 0, num_proj do
        self.mappings[i].source_col_idx = i
        self.mappings[i].dest_col_idx = i
        self.mappings[i].is_scale_mul = false
        self.mappings[i].scale_factor = 1.0
    end
end

terra PhysicalProject:set_passthrough(proj_idx: uint32, src_idx: uint32)
    if proj_idx >= self.num_projections then return end
    self.mappings[proj_idx].source_col_idx = src_idx
    self.mappings[proj_idx].dest_col_idx = proj_idx
    self.mappings[proj_idx].is_scale_mul = false
end

terra PhysicalProject:set_scaled_col(proj_idx: uint32, src_idx: uint32, factor: double)
    if proj_idx >= self.num_projections then return end
    self.mappings[proj_idx].source_col_idx = src_idx
    self.mappings[proj_idx].dest_col_idx = proj_idx
    self.mappings[proj_idx].is_scale_mul = true
    self.mappings[proj_idx].scale_factor = factor
end

terra PhysicalProject:execute(input_chunk: &DataChunk, output_chunk: &DataChunk)
    var n = input_chunk.num_rows
    output_chunk.num_rows = n
    output_chunk.has_selection = false

    for p = 0, self.num_projections do
        var src_col_idx = self.mappings[p].source_col_idx
        var dst_col_idx = self.mappings[p].dest_col_idx
        var src_col = input_chunk:get_column(src_col_idx)
        var dst_col = output_chunk:get_column(dst_col_idx)

        if self.mappings[p].is_scale_mul then
            var factor = self.mappings[p].scale_factor
            for i = 0, n do
                var phys_idx = input_chunk:get_row_index(i)
                if not src_col:is_null(phys_idx) then
                    var val = src_col:get_f64(phys_idx) * factor
                    dst_col:set_f64(i, val)
                else
                    dst_col:set_null(i)
                end
            end
        else
            -- Direct passthrough
            for i = 0, n do
                var phys_idx = input_chunk:get_row_index(i)
                if not src_col:is_null(phys_idx) then
                    var tid = src_col.data_type.type_id
                    if tid == types.VARCHAR then
                        dst_col:set_string(i, src_col:get_string(phys_idx))
                    elseif tid == types.FLOAT or tid == types.DOUBLE then
                        dst_col:set_f64(i, src_col:get_f64(phys_idx))
                    else
                        dst_col:set_i64(i, src_col:get_i64(phys_idx))
                    end
                else
                    dst_col:set_null(i)
                end
            end
        end
    end
end

project.PhysicalProject = PhysicalProject
return project
