-- Test suite for Quarry columnar storage subsystem

local C = require("src.common.c").C
local types = require("src.types.type")
local null_mask = require("src.storage/null_mask")
local col = require("src.storage/column")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")
local cat = require("src.storage/catalog")

terra run_storage_tests() : int
    C.printf("=== Running Quarry Columnar Storage Tests ===\n")

    -- Test 1: ValidityMask
    var mask : null_mask.ValidityMask
    mask:init(128)
    if not mask:is_valid(10) or not mask:is_valid(100) then
        C.printf("FAIL: initially all bits should be valid\n")
        return 1
    end
    mask:set_null(42)
    if mask:is_valid(42) or not mask:is_null(42) then
        C.printf("FAIL: bit 42 should be null\n")
        return 1
    end
    if mask:count_null() ~= 1 or mask:count_valid() ~= 127 then
        C.printf("FAIL: count_null expected 1, got %u\n", mask:count_null())
        return 1
    end
    mask:destroy()
    C.printf("PASS: ValidityMask 64-bit word bitmap indexing and counting\n")

    -- Test 2: ColumnVector
    var col_i64 : col.ColumnVector
    var dt_i64 = types.make_type(types.INT64, 0)
    col_i64:init(dt_i64, 100)
    for i = 0, 100 do
        col_i64:set_i64(i, [int64](i * 10))
    end
    for i = 0, 100 do
        if col_i64:get_i64(i) ~= [int64](i * 10) then
            C.printf("FAIL: col_i64 mismatch at %u\n", i)
            return 1
        end
    end
    col_i64:destroy()

    -- Test 3: String ColumnVector with German string views
    var col_str : col.ColumnVector
    var dt_str = types.make_type(types.VARCHAR, 0)
    col_str:init(dt_str, 50)
    col_str:set_string(0, "hyper_pipeline")
    col_str:set_string(1, "quarry_jit_engine")
    if C.strcmp(col_str:get_string(0), "hyper_pipeline") ~= 0 then
        C.printf("FAIL: string mismatch at 0\n")
        return 1
    end
    if C.strcmp(col_str:get_string(1), "quarry_jit_engine") ~= 0 then
        C.printf("FAIL: string mismatch at 1\n")
        return 1
    end
    col_str:destroy()
    C.printf("PASS: ColumnVector typed buffers and string views\n")

    -- Test 4: DataChunk and Selection Vectors
    var c : chunk.DataChunk
    var dts : types.DataType[2]
    dts[0] = types.make_type(types.INT64, 0)
    dts[1] = types.make_type(types.DOUBLE, 0)
    c:init(2, &(dts[0]), 64)

    for i = 0, 10 do
        c.columns[0]:set_i64(i, [int64](i * 5))
        c.columns[1]:set_f64(i, [double](i) * 1.5)
    end
    c.num_rows = 10

    -- Set selection vector: pick only even rows (0, 2, 4, 6, 8)
    var sel : uint32[5]
    sel[0] = 0; sel[1] = 2; sel[2] = 4; sel[3] = 6; sel[4] = 8
    c:set_selection(&(sel[0]), 5)

    if c.num_rows ~= 5 then
        C.printf("FAIL: chunk num_rows after selection expected 5, got %u\n", c.num_rows)
        return 1
    end
    for i = 0, 5 do
        var phys_idx = c:get_row_index(i)
        var expected_val = [int64](sel[i] * 5)
        if c.columns[0]:get_i64(phys_idx) ~= expected_val then
            C.printf("FAIL: selection vector access mismatch\n")
            return 1
        end
    end
    c:destroy()
    C.printf("PASS: DataChunk selection vector zero-copy row masking\n")

    -- Test 5: Table and Catalog
    var my_cat : cat.Catalog
    my_cat:init()

    var col_names : (&int8)[3]
    col_names[0] = "id"
    col_names[1] = "price"
    col_names[2] = "quantity"

    var col_tps : types.DataType[3]
    col_tps[0] = types.make_type(types.INT64, 0)
    col_tps[1] = types.make_type(types.INT64, 0)
    col_tps[2] = types.make_type(types.INT64, 0)

    var my_table = my_cat:create_table("lineitem", 3, &(col_names[0]), &(col_tps[0]))
    if my_table == nil then
        C.printf("FAIL: create_table returned nil\n")
        return 1
    end

    -- Append 3000 rows (spans across 2 chunks with standard 2048 chunk size)
    for i = 0, 3000 do
        my_table:append_row_i64_3([int64](i), [int64](i * 10), [int64](i % 50))
    end

    if my_table.total_rows ~= 3000 then
        C.printf("FAIL: total_rows expected 3000, got %llu\n", my_table.total_rows)
        return 1
    end
    if my_table.num_chunks ~= 2 then
        C.printf("FAIL: num_chunks expected 2, got %u\n", my_table.num_chunks)
        return 1
    end

    -- Verify row 2500 in chunk 1
    var c1 = my_table:get_chunk(1)
    var row_in_c1 = 2500 - 2048
    if c1.columns[0]:get_i64(row_in_c1) ~= 2500 then
        C.printf("FAIL: chunk 1 value mismatch\n")
        return 1
    end

    -- Lookup table from catalog
    var fetched_tbl = my_cat:get_table("lineitem")
    if fetched_tbl ~= my_table then
        C.printf("FAIL: catalog get_table mismatch\n")
        return 1
    end

    my_cat:destroy()
    C.printf("PASS: Relational Table multi-chunk expansion and Catalog registry\n")

    C.printf("=== ALL STORAGE TESTS PASSED (5/5) ===\n")
    return 0
end

local code = run_storage_tests()
if code ~= 0 then
    os.exit(1)
end
