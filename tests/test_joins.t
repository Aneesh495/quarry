-- Test suite for Quarry physical hash join operator

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local join = require("src.operators/hash_join")

local DataChunk = chunk.DataChunk

terra run_join_tests() : int
    C.printf("=== Running Quarry Hash Join Tests ===\n")

    -- Setup Build Chunk (Right table: id, department_id)
    var build_chunk : DataChunk
    var b_types : types.DataType[2]
    b_types[0] = types.make_type(types.INT64, 0) -- id
    b_types[1] = types.make_type(types.INT64, 0) -- department_id
    build_chunk:init(2, &(b_types[0]), 32)

    -- Insert 5 departments: (10, 100), (20, 200), (30, 300), (40, 400), (50, 500)
    for i = 0, 5 do
        var k = [int64]((i + 1) * 10)
        var v = [int64]((i + 1) * 100)
        build_chunk.columns[0]:set_i64(i, k)
        build_chunk.columns[1]:set_i64(i, v)
    end
    build_chunk.num_rows = 5

    -- Setup Probe Chunk (Left table: employee_id, dept_key)
    var probe_chunk : DataChunk
    var p_types : types.DataType[2]
    p_types[0] = types.make_type(types.INT64, 0) -- employee_id
    p_types[1] = types.make_type(types.INT64, 0) -- dept_key
    probe_chunk:init(2, &(p_types[0]), 32)

    -- 4 employees: dept_keys 20, 40, 99 (unmatched), 10
    probe_chunk.columns[0]:set_i64(0, 1)
    probe_chunk.columns[1]:set_i64(0, 20)

    probe_chunk.columns[0]:set_i64(1, 2)
    probe_chunk.columns[1]:set_i64(1, 40)

    probe_chunk.columns[0]:set_i64(2, 3)
    probe_chunk.columns[1]:set_i64(2, 99) -- Unmatched!

    probe_chunk.columns[0]:set_i64(3, 4)
    probe_chunk.columns[1]:set_i64(3, 10)
    probe_chunk.num_rows = 4

    -- Output chunk: [dept_key, department_id]
    var out_chunk : DataChunk
    var o_types : types.DataType[2]
    o_types[0] = types.make_type(types.INT64, 0)
    o_types[1] = types.make_type(types.INT64, 0)
    out_chunk:init(2, &(o_types[0]), 32)

    -- Test 1: INNER JOIN
    var inner_join : join.PhysicalHashJoin
    inner_join:init(16, 0, 1, 1, false) -- build_key=col0, build_val=col1, probe_key=col1, is_left=false
    inner_join:build(&build_chunk)

    var matched_inner = inner_join:probe(&probe_chunk, &out_chunk)
    if matched_inner ~= 3 then
        C.printf("FAIL: inner join expected 3 matches, got %u\n", matched_inner)
        return 1
    end
    C.printf("PASS: Vectorized Inner Hash Join (3 matching tuples emitted)\n")

    -- Test 2: LEFT OUTER JOIN (must retain unmatched key 99 with NULL payload)
    out_chunk:reset()
    var left_join : join.PhysicalHashJoin
    left_join:init(16, 0, 1, 1, true) -- is_left=true
    left_join:build(&build_chunk)

    var matched_left = left_join:probe(&probe_chunk, &out_chunk)
    if matched_left ~= 4 then
        C.printf("FAIL: left join expected 4 matches, got %u\n", matched_left)
        return 1
    end

    -- Verify row 2 is dept_key=99 with NULL department_id
    if out_chunk.columns[0]:get_i64(2) ~= 99 or not out_chunk.columns[1]:is_null(2) then
        C.printf("FAIL: left join row 2 should have key=99 and null payload\n")
        return 1
    end
    C.printf("PASS: Vectorized Left Outer Hash Join (unmatched tuple emitted with null payload)\n")

    build_chunk:destroy()
    probe_chunk:destroy()
    out_chunk:destroy()
    inner_join:destroy()
    left_join:destroy()

    C.printf("=== ALL JOIN TESTS PASSED (2/2) ===\n")
    return 0
end

local code = run_join_tests()
if code ~= 0 then
    os.exit(1)
end
