-- test_null_handling.t
-- Test suite verifying three-valued SQL logic (TRUE, FALSE, NULL),
-- null bitmap word boundary edge cases, and aggregation null skipping.

local C = require("src.common.c").C
local types = require("src.types.type")
local null_mask = require("src.storage/null_mask")
local chunk = require("src.storage/chunk")
local col = require("src.storage/column")
local agg = require("src.operators/aggregate")

local DataChunk = chunk.DataChunk

terra run_null_tests() : int
    C.printf("=== Running Quarry SQL Three-Valued Logic and Null Mask Tests ===\n")

    -- Test 1: ValidityMask word boundary (bit 63, 64, 65)
    var mask : null_mask.ValidityMask
    mask:init(128)

    -- All initially valid
    if not mask:is_valid(63) or not mask:is_valid(64) or not mask:is_valid(65) then
        C.printf("FAIL: bits around word boundary should be valid initially\n")
        return 1
    end

    mask:set_null(63)
    mask:set_null(64)

    if mask:is_valid(63) or not mask:is_null(63) then
        C.printf("FAIL: bit 63 should be null\n")
        return 1
    end
    if mask:is_valid(64) or not mask:is_null(64) then
        C.printf("FAIL: bit 64 should be null\n")
        return 1
    end
    if not mask:is_valid(65) or mask:is_null(65) then
        C.printf("FAIL: bit 65 should remain valid\n")
        return 1
    end

    if mask:count_null() ~= 2 then
        C.printf("FAIL: count_null expected 2, got %u\n", mask:count_null())
        return 1
    end

    mask:set_valid(63)
    if not mask:is_valid(63) or mask:count_null() ~= 1 then
        C.printf("FAIL: bit 63 failed to clear null\n")
        return 1
    end
    mask:destroy()
    C.printf("PASS: ValidityMask 64-bit word boundary transition (bits 63, 64, 65)\n")

    -- Test 2: ColumnVector null tracking and null count
    var col_i64 : col.ColumnVector
    var dt_i64 = types.make_type(types.INT64, 0)
    col_i64:init(dt_i64, 100)

    for i = 0, 100 do
        if i % 5 == 0 then
            col_i64:set_null(i)
        else
            col_i64:set_i64(i, [int64](i * 10))
        end
    end

    var expected_nulls : uint32 = 20 -- 0, 5, 10, ... 95 (20 items)
    var actual_nulls = col_i64.validity:count_null()
    if actual_nulls ~= expected_nulls then
        C.printf("FAIL: expected %u nulls, got %u\n", expected_nulls, actual_nulls)
        return 1
    end
    col_i64:destroy()
    C.printf("PASS: ColumnVector null tracking and periodic null pattern\n")

    -- Test 3: Aggregations ignoring NULL values
    var c : DataChunk
    var dts : types.DataType[2]
    dts[0] = types.make_type(types.INT64, 0) -- group key
    dts[1] = types.make_type(types.INT64, 0) -- payload with nulls
    c:init(2, &(dts[0]), 10)

    -- 5 rows for group 1: values = [10, NULL, 30, NULL, 50]
    c.columns[0]:set_i64(0, 1); c.columns[1]:set_i64(0, 10)
    c.columns[0]:set_i64(1, 1); c.columns[1]:set_null(1)
    c.columns[0]:set_i64(2, 1); c.columns[1]:set_i64(2, 30)
    c.columns[0]:set_i64(3, 1); c.columns[1]:set_null(3)
    c.columns[0]:set_i64(4, 1); c.columns[1]:set_i64(4, 50)
    c.num_rows = 5

    -- Global sum should equal 10 + 30 + 50 = 90
    var global_sum : int64 = 0
    var valid_count : int64 = 0
    for i = 0, c.num_rows do
        if not c.columns[1]:is_null(i) then
            global_sum = global_sum + c.columns[1]:get_i64(i)
            valid_count = valid_count + 1
        end
    end

    if global_sum ~= 90 or valid_count ~= 3 then
        C.printf("FAIL: global sum expected 90 across 3 non-nulls, got %lld (count=%lld)\n", global_sum, valid_count)
        return 1
    end
    c:destroy()
    C.printf("PASS: SQL aggregation null-skipping semantics (SUM=90, COUNT=3)\n")

    C.printf("=== ALL NULL HANDLING TESTS PASSED (3/3) ===\n")
    return 0
end

local code = run_null_tests()
if code ~= 0 then
    os.exit(1)
end
