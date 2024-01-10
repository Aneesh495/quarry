-- Quarry physical vectorized filter operator
-- Evaluates relational predicates and populates zero-copy selection vectors.

local C = require("src.common.c").C
local token = require("src.parser/token")
local ast = require("src.parser/ast")
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk
local ExprNode = ast.ExprNode

local filter = {}

struct PhysicalFilter {
    predicate: &ExprNode,
    temp_sel: uint32[2048]
}

terra PhysicalFilter:init(pred: &ExprNode)
    self.predicate = pred
end

-- Evaluates a single comparison between a column and an integer literal
terra PhysicalFilter:execute_i64_cmp(c: &DataChunk, col_idx: uint32, op: int32, target: int64) : uint32
    var col_ptr = c:get_column(col_idx)
    if col_ptr == nil then return 0 end

    var match_count : uint32 = 0
    var n = c.num_rows

    for i = 0, n do
        var phys_idx = c:get_row_index(i)
        if not col_ptr:is_null(phys_idx) then
            var val = col_ptr:get_i64(phys_idx)
            var pass = false

            if op == token.TOKEN_EQ then
                pass = (val == target)
            elseif op == token.TOKEN_NEQ then
                pass = (val ~= target)
            elseif op == token.TOKEN_GT then
                pass = (val > target)
            elseif op == token.TOKEN_GTE then
                pass = (val >= target)
            elseif op == token.TOKEN_LT then
                pass = (val < target)
            elseif op == token.TOKEN_LTE then
                pass = (val <= target)
            end

            if pass then
                self.temp_sel[match_count] = phys_idx
                match_count = match_count + 1
            end
        end
    end

    c:set_selection(&(self.temp_sel[0]), match_count)
    return match_count
end

-- Evaluates a comparison between a column and a double literal
terra PhysicalFilter:execute_f64_cmp(c: &DataChunk, col_idx: uint32, op: int32, target: double) : uint32
    var col_ptr = c:get_column(col_idx)
    if col_ptr == nil then return 0 end

    var match_count : uint32 = 0
    var n = c.num_rows

    for i = 0, n do
        var phys_idx = c:get_row_index(i)
        if not col_ptr:is_null(phys_idx) then
            var val = col_ptr:get_f64(phys_idx)
            var pass = false

            if op == token.TOKEN_EQ then
                pass = (val == target)
            elseif op == token.TOKEN_NEQ then
                pass = (val ~= target)
            elseif op == token.TOKEN_GT then
                pass = (val > target)
            elseif op == token.TOKEN_GTE then
                pass = (val >= target)
            elseif op == token.TOKEN_LT then
                pass = (val < target)
            elseif op == token.TOKEN_LTE then
                pass = (val <= target)
            end

            if pass then
                self.temp_sel[match_count] = phys_idx
                match_count = match_count + 1
            end
        end
    end

    c:set_selection(&(self.temp_sel[0]), match_count)
    return match_count
end

filter.PhysicalFilter = PhysicalFilter
return filter
