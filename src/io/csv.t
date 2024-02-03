-- Quarry CSV reader and writer subsystem
-- Streams comma-separated tabular records directly into columnar chunk buffers.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")

local Table = tbl.Table
local DataChunk = chunk.DataChunk

local csv = {}

-- Parses a line of comma-separated tokens into values and appends to Table
local terra parse_csv_line_fn(line: &int8, t: &Table) : bool
    if line == nil or line[0] == 0 or line[0] == 10 or line[0] == 13 then return false end

    var c = t:get_or_create_active_chunk()
    var r = c.num_rows

    var pos : uint32 = 0
    var col_idx : uint32 = 0
    var buf : int8[256]

    while line[pos] ~= 0 and col_idx < t.num_columns do
        var b_idx : uint32 = 0
        while line[pos] ~= 0 and line[pos] ~= 44 and line[pos] ~= 10 and line[pos] ~= 13 and b_idx < 255 do
            buf[b_idx] = line[pos]
            b_idx = b_idx + 1
            pos = pos + 1
        end
        buf[b_idx] = 0

        var target_col = c:get_column(col_idx)
        var tid = target_col.data_type.type_id

        if tid == types.VARCHAR then
            target_col:set_string(r, &(buf[0]))
        elseif tid == types.FLOAT or tid == types.DOUBLE then
            target_col:set_f64(r, C.strtod(&(buf[0]), nil))
        else
            target_col:set_i64(r, C.strtoll(&(buf[0]), nil, 10))
        end

        col_idx = col_idx + 1
        if line[pos] == 44 then pos = pos + 1 end -- consume ','
    end

    c.num_rows = r + 1
    t.total_rows = t.total_rows + 1
    return true
end

-- Writes a Table to CSV file
local terra export_csv_fn(t: &Table, file_path: &int8) : bool
    var fd = C.open(file_path, 0x0601, 0644) -- O_CREAT | O_WRONLY | O_TRUNC
    if fd < 0 then return false end

    var line_buf : int8[1024]
    var offset : int32 = 0

    -- Write header
    for i = 0, t.num_columns do
        if i > 0 then
            offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, ",")
        end
        offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, "%s", &(t.columns[i].name[0]))
    end
    offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, "\n")
    C.write(fd, &(line_buf[0]), offset)

    -- Write rows
    for c_idx = 0, t.num_chunks do
        var c = t:get_chunk(c_idx)
        for r = 0, c.num_rows do
            var phys_idx = c:get_row_index(r)
            offset = 0
            for col_idx = 0, t.num_columns do
                if col_idx > 0 then
                    offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, ",")
                end
                var col_ptr = c:get_column(col_idx)
                var tid = col_ptr.data_type.type_id
                if tid == types.VARCHAR then
                    offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, "%s", col_ptr:get_string(phys_idx))
                elseif tid == types.FLOAT or tid == types.DOUBLE then
                    offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, "%.2f", col_ptr:get_f64(phys_idx))
                else
                    offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, "%lld", col_ptr:get_i64(phys_idx))
                end
            end
            offset = offset + C.snprintf(&(line_buf[offset]), 1024 - offset, "\n")
            C.write(fd, &(line_buf[0]), offset)
        end
    end

    C.close(fd)
    return true
end

csv.parse_csv_line = parse_csv_line_fn
csv.export_csv = export_csv_fn
return csv
