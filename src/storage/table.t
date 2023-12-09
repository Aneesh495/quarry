-- Quarry in-memory relational table subsystem
-- Chunked columnar table structure supporting morsel-driven scanning and dynamic append.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")

local tbl = {}

tbl.MAX_CHUNKS = 4096
tbl.MAX_COLUMNS = 64
tbl.NAME_LEN = 64

struct TableColumnMeta {
    name: int8[64],
    data_type: types.DataType
}

struct Table {
    name: int8[64],
    num_columns: uint32,
    columns: TableColumnMeta[64],
    num_chunks: uint32,
    chunk_capacity: uint32,
    chunks: &(&chunk.DataChunk),
    total_rows: uint64,
    default_chunk_size: uint32
}

terra Table:init(name: &int8, num_cols: uint32, col_names: &(&int8), col_types: &types.DataType)
    if name ~= nil then
        C.strncpy(&(self.name[0]), name, 63)
        self.name[63] = 0
    else
        self.name[0] = 0
    end

    self.num_columns = num_cols
    self.num_chunks = 0
    self.chunk_capacity = 16
    self.total_rows = 0
    self.default_chunk_size = chunk.STANDARD_CHUNK_SIZE

    self.chunks = [&(&chunk.DataChunk)](C.malloc(self.chunk_capacity * sizeof(&chunk.DataChunk)))

    for i = 0, num_cols do
        C.strncpy(&(self.columns[i].name[0]), col_names[i], 63)
        self.columns[i].name[63] = 0
        self.columns[i].data_type = col_types[i]
    end
end

terra Table:destroy()
    for i = 0, self.num_chunks do
        self.chunks[i]:destroy()
        C.free(self.chunks[i])
    end
    if self.chunks ~= nil then
        C.free(self.chunks)
        self.chunks = nil
    end
    self.num_chunks = 0
    self.total_rows = 0
end

terra Table:get_column_types() : types.DataType[64]
    var dt_arr : types.DataType[64]
    for i = 0, self.num_columns do
        dt_arr[i] = self.columns[i].data_type
    end
    return dt_arr
end

terra Table:new_chunk() : &chunk.DataChunk
    if self.num_chunks >= self.chunk_capacity then
        var new_cap = self.chunk_capacity * 2
        var new_chunks = [&(&chunk.DataChunk)](C.realloc(self.chunks, new_cap * sizeof(&chunk.DataChunk)))
        self.chunks = new_chunks
        self.chunk_capacity = new_cap
    end

    var c_ptr = [&chunk.DataChunk](C.malloc(sizeof(chunk.DataChunk)))
    var dt_arr = self:get_column_types()
    c_ptr:init(self.num_columns, &(dt_arr[0]), self.default_chunk_size)

    self.chunks[self.num_chunks] = c_ptr
    self.num_chunks = self.num_chunks + 1
    return c_ptr
end

terra Table:get_or_create_active_chunk() : &chunk.DataChunk
    if self.num_chunks == 0 then
        return self:new_chunk()
    end
    var last = self.chunks[self.num_chunks - 1]
    if last.num_rows >= last.capacity then
        return self:new_chunk()
    end
    return last
end

terra Table:find_column_index(col_name: &int8) : int32
    for i = 0, self.num_columns do
        if C.strcmp(&(self.columns[i].name[0]), col_name) == 0 then
            return [int32](i)
        end
    end
    return -1
end

terra Table:append_row_i64_3(v0: int64, v1: int64, v2: int64)
    var c = self:get_or_create_active_chunk()
    var r = c.num_rows
    c.columns[0]:set_i64(r, v0)
    c.columns[1]:set_i64(r, v1)
    c.columns[2]:set_i64(r, v2)
    c.num_rows = r + 1
    self.total_rows = self.total_rows + 1
end

terra Table:get_chunk(idx: uint32) : &chunk.DataChunk
    if idx >= self.num_chunks then return nil end
    return self.chunks[idx]
end

tbl.Table = Table
return tbl
