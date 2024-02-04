-- Test suite for Quarry I/O, binary persistence, CSV, and Arrow bridge

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")
local binary = require("src.io/binary")
local csv = require("src.io/csv")
local arrow = require("src.io/arrow")

local Table = tbl.Table
local DataChunk = chunk.DataChunk

terra run_io_tests() : int
    C.printf("=== Running Quarry I/O and Persistence Tests ===\n")

    -- Setup table
    var col_names : (&int8)[2]
    col_names[0] = "id"
    col_names[1] = "val"

    var col_tps : types.DataType[2]
    col_tps[0] = types.make_type(types.INT64, 0)
    col_tps[1] = types.make_type(types.INT64, 0)

    var orig_table : Table
    orig_table:init("test_io_table", 2, &(col_names[0]), &(col_tps[0]))

    for i = 0, 100 do
        var c = orig_table:get_or_create_active_chunk()
        var r = c.num_rows
        c.columns[0]:set_i64(r, [int64](i))
        c.columns[1]:set_i64(r, [int64](i * 42))
        c.num_rows = r + 1
        orig_table.total_rows = orig_table.total_rows + 1
    end

    -- Test 1: Native binary format roundtrip
    var bin_path = "/tmp/test_table.quarry"
    var save_ok = binary.save_table(&orig_table, bin_path)
    if not save_ok then
        C.printf("FAIL: save_table failed\n")
        return 1
    end

    var loaded_table : Table
    var load_ok = binary.load_table(bin_path, &loaded_table)
    if not load_ok or loaded_table.total_rows ~= 100 then
        C.printf("FAIL: load_table failed or total_rows mismatch (got %llu)\n", loaded_table.total_rows)
        return 1
    end

    var c0 = loaded_table:get_chunk(0)
    if c0.columns[0]:get_i64(50) ~= 50 or c0.columns[1]:get_i64(50) ~= 2100 then
        C.printf("FAIL: loaded binary data mismatch\n")
        return 1
    end
    C.printf("PASS: Native .quarry binary persistence serialization and deserialization\n")

    -- Test 2: CSV parsing and export
    var csv_path = "/tmp/test_export.csv"
    var csv_ok = csv.export_csv(&orig_table, csv_path)
    if not csv_ok then
        C.printf("FAIL: export_csv failed\n")
        return 1
    end

    var csv_table : Table
    csv_table:init("csv_import", 2, &(col_names[0]), &(col_tps[0]))
    csv.parse_csv_line("999,8888", &csv_table)
    if csv_table.total_rows ~= 1 then
        C.printf("FAIL: parse_csv_line failed\n")
        return 1
    end
    var c_csv = csv_table:get_chunk(0)
    if c_csv.columns[0]:get_i64(0) ~= 999 or c_csv.columns[1]:get_i64(0) ~= 8888 then
        C.printf("FAIL: csv parsed values mismatch\n")
        return 1
    end
    C.printf("PASS: CSV parser streaming and file export\n")

    -- Test 3: Arrow C Data Interface zero-copy export
    var arr : arrow.ArrowArray
    var bufs : (&opaque)[2]
    arrow.export_column_to_arrow(c0, 0, &arr, &(bufs[0]))
    if arr.length ~= 100 or arr.n_buffers ~= 2 or arr.buffers == nil then
        C.printf("FAIL: export_column_to_arrow validation failed\n")
        return 1
    end
    C.printf("PASS: Apache Arrow C Data Interface zero-copy buffer export\n")

    orig_table:destroy()
    loaded_table:destroy()
    csv_table:destroy()

    C.printf("=== ALL I/O TESTS PASSED (3/3) ===\n")
    return 0
end

local code = run_io_tests()
if code ~= 0 then
    os.exit(1)
end
