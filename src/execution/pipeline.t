-- Quarry push-based pipeline execution orchestrator
-- Couples morsel queues, physical operators, and result sinks into high-throughput execution runs.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")
local morsel = require("src.execution/morsel")
local ctx = require("src.execution/context")

local DataChunk = chunk.DataChunk
local Table = tbl.Table
local MorselQueue = morsel.MorselQueue
local ExecutionContext = ctx.ExecutionContext

local pipe = {}

struct PipelineResult {
    total_tuples: uint64,
    num_chunks: uint32,
    execution_time_us: double
}

-- Simple in-memory sink collecting output chunks
struct ResultCollector {
    capacity: uint32,
    num_chunks: uint32,
    total_tuples: uint64,
    chunks: &(&DataChunk)
}

terra ResultCollector:init()
    self.capacity = 16
    self.num_chunks = 0
    self.total_tuples = 0
    self.chunks = [&(&DataChunk)](C.malloc(self.capacity * 8))
end

terra ResultCollector:destroy()
    for i = 0, self.num_chunks do
        self.chunks[i]:destroy()
        C.free(self.chunks[i])
    end
    if self.chunks ~= nil then
        C.free(self.chunks)
        self.chunks = nil
    end
    self.num_chunks = 0
    self.total_tuples = 0
end

terra ResultCollector:add_chunk(src_chunk: &DataChunk)
    if self.num_chunks >= self.capacity then
        var new_cap = self.capacity * 2
        self.chunks = [&(&DataChunk)](C.realloc(self.chunks, new_cap * 8))
        self.capacity = new_cap
    end

    -- Allocate and copy
    var c_copy = [&DataChunk](C.malloc(sizeof(DataChunk)))
    var dt_arr : types.DataType[64]
    for i = 0, src_chunk.num_columns do
        dt_arr[i] = src_chunk.columns[i].data_type
    end
    c_copy:init(src_chunk.num_columns, &(dt_arr[0]), src_chunk.capacity)

    var n = src_chunk.num_rows
    c_copy.num_rows = n
    c_copy.has_selection = src_chunk.has_selection
    if src_chunk.has_selection then
        C.memcpy(c_copy.selection_vector, src_chunk.selection_vector, n * sizeof(uint32))
    end

    for col_idx = 0, src_chunk.num_columns do
        var byte_width = src_chunk.columns[col_idx].data_type.byte_width
        C.memcpy(c_copy.columns[col_idx].raw_data, src_chunk.columns[col_idx].raw_data, src_chunk.capacity * byte_width)
        C.memcpy(c_copy.columns[col_idx].validity.words, src_chunk.columns[col_idx].validity.words, src_chunk.columns[col_idx].validity.num_words * 8)
    end

    self.chunks[self.num_chunks] = c_copy
    self.num_chunks = self.num_chunks + 1
    self.total_tuples = self.total_tuples + n
end

pipe.ResultCollector = ResultCollector
pipe.PipelineResult = PipelineResult
return pipe
