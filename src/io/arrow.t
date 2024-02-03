-- Quarry Apache Arrow C Data Interface bridge
-- Zero-copy columnar sharing with PyArrow, DuckDB, Polars, and Pandas runtimes.

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk

local arrow = {}

-- Standard Apache Arrow C Data Interface ABI definitions
struct ArrowSchema {
    format: &int8,
    name: &int8,
    metadata: &int8,
    flags: int64,
    n_children: int64,
    children: &(&ArrowSchema),
    dictionary: &ArrowSchema,
    release: &(&ArrowSchema -> {}),
    private_data: &opaque
}

struct ArrowArray {
    length: int64,
    null_count: int64,
    offset: int64,
    n_buffers: int64,
    n_children: int64,
    buffers: &(&opaque),
    children: &(&ArrowArray),
    dictionary: &ArrowArray,
    release: &(&ArrowArray -> {}),
    private_data: &opaque
}

-- Exports a ColumnVector to an ArrowArray structure with zero data copies
local terra export_column_to_arrow_fn(c: &DataChunk, col_idx: uint32, out_arr: &ArrowArray, buffer_ptrs: &(&opaque))
    var col_ptr = c:get_column(col_idx)
    out_arr.length = [int64](c.num_rows)
    out_arr.null_count = [int64](col_ptr.validity:count_null())
    out_arr.offset = 0
    out_arr.n_buffers = 2
    out_arr.n_children = 0
    out_arr.children = nil
    out_arr.dictionary = nil
    out_arr.release = nil
    out_arr.private_data = nil

    -- Buffer 0: Validity bitmap
    buffer_ptrs[0] = [&opaque](col_ptr.validity.words)
    -- Buffer 1: Raw contiguous data buffer
    buffer_ptrs[1] = [&opaque](col_ptr.raw_data)
    out_arr.buffers = buffer_ptrs
end

arrow.ArrowSchema = ArrowSchema
arrow.ArrowArray = ArrowArray
arrow.export_column_to_arrow = export_column_to_arrow_fn

return arrow
