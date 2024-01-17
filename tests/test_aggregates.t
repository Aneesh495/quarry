-- Test suite for Quarry physical hash aggregate operator

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local agg = require("src.operators/aggregate")

local DataChunk = chunk.DataChunk

terra run_aggregate_tests() : int
    C.printf("=== Running Quarry Hash Aggregate Tests ===\n")

    -- Setup input chunk: [category_id, amount]
    var in_chunk : DataChunk
    var in_types : types.DataType[2]
    in_types[0] = types.make_type(types.INT64, 0) -- category_id
    in_types[1] = types.make_type(types.INT64, 0) -- amount
    in_chunk:init(2, &(in_types[0]), 32)

    -- Insert 6 rows:
    -- cat 1: 100, 200, 300 (count=3, sum=600)
    -- cat 2: 50, 75 (count=2, sum=125)
    -- cat 3: 1000 (count=1, sum=1000)
    in_chunk.columns[0]:set_i64(0, 1); in_chunk.columns[1]:set_i64(0, 100)
    in_chunk.columns[0]:set_i64(1, 1); in_chunk.columns[1]:set_i64(1, 200)
    in_chunk.columns[0]:set_i64(2, 2); in_chunk.columns[1]:set_i64(2, 50)
    in_chunk.columns[0]:set_i64(3, 1); in_chunk.columns[1]:set_i64(3, 300)
    in_chunk.columns[0]:set_i64(4, 2); in_chunk.columns[1]:set_i64(4, 75)
    in_chunk.columns[0]:set_i64(5, 3); in_chunk.columns[1]:set_i64(5, 1000)
    in_chunk.num_rows = 6

    -- Output chunk: [category_id, count, sum]
    var out_chunk : DataChunk
    var o_types : types.DataType[3]
    o_types[0] = types.make_type(types.INT64, 0)
    o_types[1] = types.make_type(types.INT64, 0)
    o_types[2] = types.make_type(types.INT64, 0)
    out_chunk:init(3, &(o_types[0]), 32)

    -- Test 1: GROUP BY category_id
    var gb_agg : agg.PhysicalHashAggregate
    gb_agg:init(16, 0, 1, true)
    gb_agg:sink(&in_chunk)

    if gb_agg.num_groups ~= 3 then
        C.printf("FAIL: expected 3 distinct groups, got %u\n", gb_agg.num_groups)
        return 1
    end

    var emitted = gb_agg:emit(&out_chunk)
    if emitted ~= 3 then
        C.printf("FAIL: expected 3 emitted groups, got %u\n", emitted)
        return 1
    end

    -- Verify category 1 has count=3 and sum=600
    var found_cat1 = false
    for i = 0, emitted do
        if out_chunk.columns[0]:get_i64(i) == 1 then
            if out_chunk.columns[1]:get_i64(i) ~= 3 or out_chunk.columns[2]:get_i64(i) ~= 600 then
                C.printf("FAIL: category 1 agg mismatch (count=%lld, sum=%lld)\n",
                    out_chunk.columns[1]:get_i64(i), out_chunk.columns[2]:get_i64(i))
                return 1
            end
            found_cat1 = true
        end
    end
    if not found_cat1 then
        C.printf("FAIL: category 1 not found in emitted chunk\n")
        return 1
    end
    C.printf("PASS: Group-By Hash Aggregate (COUNT and SUM per category)\n")

    -- Test 2: Global Scalar Aggregate (no GROUP BY)
    out_chunk:reset()
    var scalar_agg : agg.PhysicalHashAggregate
    scalar_agg:init(16, 0, 1, false)
    scalar_agg:sink(&in_chunk)

    var emitted_scalar = scalar_agg:emit(&out_chunk)
    if emitted_scalar ~= 1 then
        C.printf("FAIL: scalar agg expected 1 row, got %u\n", emitted_scalar)
        return 1
    end

    -- Total count=6, total sum = 600 + 125 + 1000 = 1725
    var total_cnt = out_chunk.columns[0]:get_i64(0)
    var total_sum = out_chunk.columns[1]:get_i64(0)
    if total_cnt ~= 6 or total_sum ~= 1725 then
        C.printf("FAIL: scalar agg mismatch (count=%lld, sum=%lld)\n", total_cnt, total_sum)
        return 1
    end
    C.printf("PASS: Global Scalar Aggregate (total count=6, total sum=1725)\n")

    in_chunk:destroy()
    out_chunk:destroy()
    gb_agg:destroy()
    scalar_agg:destroy()

    C.printf("=== ALL AGGREGATE TESTS PASSED (2/2) ===\n")
    return 0
end

local code = run_aggregate_tests()
if code ~= 0 then
    os.exit(1)
end
