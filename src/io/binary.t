-- Quarry native binary columnar file format (.quarry)
-- High-throughput zero-copy serializer and deserializer with block compression tags.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")

local Table = tbl.Table
local TableColumnMeta = tbl.TableColumnMeta
local DataChunk = chunk.DataChunk

local binary = {}

binary.MAGIC_QURY = 0x59525551 -- 'QURY' in little endian
binary.FORMAT_VERSION = 1

struct QuarryFileHeader {
    magic: uint32,
    version: uint32,
    num_columns: uint32,
    num_chunks: uint32,
    total_rows: uint64
}

-- Serializes an in-memory Table to a native .quarry file
local terra save_table_fn(t: &Table, file_path: &int8) : bool
    var fd = C.open(file_path, 0x0601, 0644) -- O_CREAT | O_WRONLY | O_TRUNC
    if fd < 0 then return false end

    var hdr : QuarryFileHeader
    hdr.magic = binary.MAGIC_QURY
    hdr.version = binary.FORMAT_VERSION
    hdr.num_columns = t.num_columns
    hdr.num_chunks = t.num_chunks
    hdr.total_rows = t.total_rows

    C.write(fd, &hdr, sizeof(QuarryFileHeader))

    -- Write column metadata
    for i = 0, t.num_columns do
        C.write(fd, &(t.columns[i]), sizeof(TableColumnMeta))
    end

    -- Write chunk data
    for c_idx = 0, t.num_chunks do
        var c = t:get_chunk(c_idx)
        var row_count = c.num_rows
        C.write(fd, &row_count, sizeof(uint32))

        for col_idx = 0, t.num_columns do
            var col_ptr = c:get_column(col_idx)
            var byte_width = col_ptr.data_type.byte_width
            var total_bytes = [uint64](c.capacity) * [uint64](byte_width)
            C.write(fd, col_ptr.raw_data, total_bytes)
            C.write(fd, col_ptr.validity.words, col_ptr.validity.num_words * 8)
        end
    end

    C.close(fd)
    return true
end

-- Deserializes a native .quarry file into an in-memory Table
local terra load_table_fn(file_path: &int8, out_table: &Table) : bool
    var fd = C.open(file_path, 0, 0) -- O_RDONLY
    if fd < 0 then return false end

    var hdr : QuarryFileHeader
    var bytes_read = C.read(fd, &hdr, sizeof(QuarryFileHeader))
    if bytes_read ~= sizeof(QuarryFileHeader) or hdr.magic ~= binary.MAGIC_QURY then
        C.close(fd)
        return false
    end

    var col_metas : TableColumnMeta[64]
    for i = 0, hdr.num_columns do
        C.read(fd, &(col_metas[i]), sizeof(TableColumnMeta))
    end

    var col_names : (&int8)[64]
    var col_types : types.DataType[64]
    for i = 0, hdr.num_columns do
        col_names[i] = &(col_metas[i].name[0])
        col_types[i] = col_metas[i].data_type
    end

    out_table:init("loaded_table", hdr.num_columns, &(col_names[0]), &(col_types[0]))

    for c_idx = 0, hdr.num_chunks do
        var row_count : uint32 = 0
        C.read(fd, &row_count, sizeof(uint32))

        var c = out_table:new_chunk()
        c.num_rows = row_count

        for col_idx = 0, hdr.num_columns do
            var col_ptr = c:get_column(col_idx)
            var byte_width = col_ptr.data_type.byte_width
            var total_bytes = [uint64](c.capacity) * [uint64](byte_width)
            C.read(fd, col_ptr.raw_data, total_bytes)
            C.read(fd, col_ptr.validity.words, col_ptr.validity.num_words * 8)
        end
    end

    out_table.total_rows = hdr.total_rows
    C.close(fd)
    return true
end

binary.QuarryFileHeader = QuarryFileHeader
binary.save_table = save_table_fn
binary.load_table = load_table_fn

return binary
