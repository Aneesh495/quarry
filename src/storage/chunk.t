-- Quarry DataChunk morsel container
-- Standard unit of pipeline execution with selection vector for zero-copy filtering.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local col = require("src.storage/column")

local chunk = {}

-- Standard default morsel chunk size for CPU L1/L2 cache locality
chunk.STANDARD_CHUNK_SIZE = 2048
chunk.MAX_COLUMNS = 64

struct DataChunk {
    capacity: uint32,
    num_rows: uint32,
    num_columns: uint32,
    has_selection: bool,
    selection_vector: &uint32,
    columns: col.ColumnVector[64]
}

terra DataChunk:init(num_cols: uint32, col_types: &types.DataType, capacity: uint32)
    self.capacity = capacity
    self.num_rows = 0
    self.num_columns = num_cols
    self.has_selection = false
    self.selection_vector = [&uint32](alloc.aligned_alloc(capacity * sizeof(uint32), alloc.CACHE_LINE))

    for i = 0, num_cols do
        self.columns[i]:init(col_types[i], capacity)
    end
end

terra DataChunk:destroy()
    for i = 0, self.num_columns do
        self.columns[i]:destroy()
    end
    if self.selection_vector ~= nil then
        alloc.aligned_free(self.selection_vector)
        self.selection_vector = nil
    end
    self.num_columns = 0
    self.num_rows = 0
    self.capacity = 0
end

terra DataChunk:reset()
    self.num_rows = 0
    self.has_selection = false
    for i = 0, self.num_columns do
        self.columns[i]:reset()
    end
end

terra DataChunk:get_row_index(logical_idx: uint32) : uint32
    if self.has_selection then
        return self.selection_vector[logical_idx]
    end
    return logical_idx
end

terra DataChunk:set_selection(sel_indices: &uint32, count: uint32)
    self.has_selection = true
    self.num_rows = count
    C.memcpy(self.selection_vector, sel_indices, count * sizeof(uint32))
end

terra DataChunk:clear_selection()
    self.has_selection = false
end

terra DataChunk:get_column(col_idx: uint32) : &col.ColumnVector
    if col_idx >= self.num_columns then return nil end
    return &(self.columns[col_idx])
end

chunk.DataChunk = DataChunk
return chunk
