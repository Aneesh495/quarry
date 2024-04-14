-- test_arrow_roundtrip.t
-- Test suite verifying Apache Arrow C Data Interface zero-copy bridge
-- for columnar sharing across data ecosystems.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local arrow = require("src.io/arrow")

local DataChunk = chunk.DataChunk

terra run_arrow_roundtrip_tests() : int
    C.printf("=== Running Quarry Apache Arrow C Data Interface Tests ===\n")

    -- 1. Initialize DataChunk with INT64 and DOUBLE columns
    var c : DataChunk
    var dts : types.DataType[2]
    dts[0] = types.make_type(types.INT64, 0)
    dts[1] = types.make_type(types.DOUBLE, 0)
    c:init(2, &(dts[0]), 50)

    for i = 0, 50 do
        if i % 5 == 0 then
            c.columns[0]:set_null(i)
            c.columns[1]:set_f64(i, [double](i) * 1.5)
        else
            c.columns[0]:set_i64(i, [int64](i * 100))
            c.columns[1]:set_f64(i, [double](i) * 1.5)
        end
    end
    c.num_rows = 50

    -- 2. Export column 0 (INT64 with nulls) to ArrowArray
    var arr0 : arrow.ArrowArray
    var bufs0 : (&opaque)[2]
    arrow.export_column_to_arrow(&c, 0, &arr0, &(bufs0[0]))

    if arr0.length ~= 50 then
        C.printf("FAIL: ArrowArray length expected 50, got %lld\n", arr0.length)
        return 1
    end
    if arr0.null_count ~= 10 then
        C.printf("FAIL: ArrowArray null_count expected 10, got %lld\n", arr0.null_count)
        return 1
    end
    if arr0.n_buffers ~= 2 then
        C.printf("FAIL: ArrowArray n_buffers expected 2, got %lld\n", arr0.n_buffers)
        return 1
    end

    -- Verify zero-copy buffer pointer identities
    if arr0.buffers[0] ~= [&opaque](c.columns[0].validity.words) then
        C.printf("FAIL: buffer 0 pointer should equal validity bitmap words\n")
        return 1
    end
    if arr0.buffers[1] ~= [&opaque](c.columns[0].raw_data) then
        C.printf("FAIL: buffer 1 pointer should equal column raw data\n")
        return 1
    end

    -- Read directly through Arrow buffer pointer
    var raw_arrow_i64 = [&int64](arr0.buffers[1])
    for i = 0, 50 do
        if i % 5 ~= 0 then
            if raw_arrow_i64[i] ~= [int64](i * 100) then
                C.printf("FAIL: raw arrow value mismatch at %u\n", i)
                return 1
            end
        end
    end
    C.printf("PASS: INT64 column exported to ArrowArray with zero-copy buffer mapping\n")

    -- 3. Export column 1 (DOUBLE) to ArrowArray
    var arr1 : arrow.ArrowArray
    var bufs1 : (&opaque)[2]
    arrow.export_column_to_arrow(&c, 1, &arr1, &(bufs1[0]))

    if arr1.length ~= 50 or arr1.null_count ~= 0 then
        C.printf("FAIL: column 1 arrow export metadata mismatch\n")
        return 1
    end

    var raw_arrow_f64 = [&double](arr1.buffers[1])
    for i = 0, 50 do
        var expected = [double](i) * 1.5
        if C.fabs(raw_arrow_f64[i] - expected) > 1e-6 then
            C.printf("FAIL: arrow float64 value mismatch at %u\n", i)
            return 1
        end
    end
    C.printf("PASS: DOUBLE column exported to ArrowArray with zero-copy buffer mapping\n")

    c:destroy()
    C.printf("=== ALL ARROW C DATA INTERFACE TESTS PASSED (2/2) ===\n")
    return 0
end

local code = run_arrow_roundtrip_tests()
if code ~= 0 then
    os.exit(1)
end
