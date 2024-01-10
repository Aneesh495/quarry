-- Quarry physical window operator
-- Computes ROW_NUMBER, RANK, and DENSE_RANK over sorted columnar chunks.

local C = require("src.common.c").C
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk

local win = {}

win.WIN_ROW_NUMBER = 1
win.WIN_RANK       = 2
win.WIN_DENSE_RANK = 3

struct PhysicalWindow {
    win_func: int32,
    order_col_idx: uint32,
    current_row: uint64,
    current_rank: uint64,
    current_dense_rank: uint64,
    prev_val: int64,
    has_prev: bool
}

terra PhysicalWindow:init(func: int32, order_col: uint32)
    self.win_func = func
    self.order_col_idx = order_col
    self.current_row = 0
    self.current_rank = 1
    self.current_dense_rank = 1
    self.prev_val = 0
    self.has_prev = false
end

-- Evaluates window function on input chunk and writes results into out_col_idx
terra PhysicalWindow:execute(c: &DataChunk, out_col_idx: uint32)
    var out_col = c:get_column(out_col_idx)
    var ord_col = c:get_column(self.order_col_idx)
    if out_col == nil or ord_col == nil then return end

    var n = c.num_rows

    for i = 0, n do
        var phys_idx = c:get_row_index(i)
        var val = ord_col:get_i64(phys_idx)
        self.current_row = self.current_row + 1

        if not self.has_prev then
            self.prev_val = val
            self.has_prev = true
            self.current_rank = 1
            self.current_dense_rank = 1
        elseif val ~= self.prev_val then
            self.current_rank = self.current_row
            self.current_dense_rank = self.current_dense_rank + 1
            self.prev_val = val
        end

        if self.win_func == win.WIN_ROW_NUMBER then
            out_col:set_i64(phys_idx, [int64](self.current_row))
        elseif self.win_func == win.WIN_RANK then
            out_col:set_i64(phys_idx, [int64](self.current_rank))
        elseif self.win_func == win.WIN_DENSE_RANK then
            out_col:set_i64(phys_idx, [int64](self.current_dense_rank))
        end
    end
end

win.PhysicalWindow = PhysicalWindow
return win
