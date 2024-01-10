-- Quarry physical table scan operator
-- Scans columnar chunks from an in-memory table.

local C = require("src.common.c").C
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")

local DataChunk = chunk.DataChunk
local Table = tbl.Table

local scan = {}

struct PhysicalScan {
    table_ptr: &Table,
    current_chunk_idx: uint32
}

terra PhysicalScan:init(target_table: &Table)
    self.table_ptr = target_table
    self.current_chunk_idx = 0
end

terra PhysicalScan:get_next_chunk() : &DataChunk
    if self.table_ptr == nil then return nil end
    if self.current_chunk_idx >= self.table_ptr.num_chunks then
        return nil
    end

    var c = self.table_ptr:get_chunk(self.current_chunk_idx)
    self.current_chunk_idx = self.current_chunk_idx + 1
    return c
end

terra PhysicalScan:reset()
    self.current_chunk_idx = 0
end

scan.PhysicalScan = PhysicalScan
return scan
