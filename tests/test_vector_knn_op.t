-- test_vector_knn_op.t
-- Test suite for Quarry PhysicalVectorKNN relational pipeline operator

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local dist = require("src.vector/distance")
local vknn = require("src.operators/vector_knn")

local DataChunk = chunk.DataChunk

terra run_vector_knn_op_test() : int
    C.printf("=== Running Quarry PhysicalVectorKNN Operator Tests ===\n")

    var in_chunk : DataChunk
    var in_types : types.DataType[2]
    in_types[0] = types.make_type(types.INT64, 0)
    in_types[1] = types.make_type(types.VECTOR_F32, 4)
    in_chunk:init(2, &(in_types[0]), 32)

    -- Vector 0: [1.0, 0.0, 0.0, 0.0] -> dist to query [1.0, 0.0, 0.0, 0.0] is 0.0
    var v0 : float[4]
    v0[0] = 1.0f; v0[1] = 0.0f; v0[2] = 0.0f; v0[3] = 0.0f
    in_chunk.columns[0]:set_i64(0, 101)
    in_chunk.columns[1]:set_vector(0, &(v0[0]), 4)

    -- Vector 1: [0.0, 1.0, 0.0, 0.0] -> dist is sqrt(2) ~ 1.414
    var v1 : float[4]
    v1[0] = 0.0f; v1[1] = 1.0f; v1[2] = 0.0f; v1[3] = 0.0f
    in_chunk.columns[0]:set_i64(1, 102)
    in_chunk.columns[1]:set_vector(1, &(v1[0]), 4)

    -- Vector 2: [0.9, 0.1, 0.0, 0.0] -> dist ~ sqrt(0.01 + 0.01) ~ 0.1414
    var v2 : float[4]
    v2[0] = 0.9f; v2[1] = 0.1f; v2[2] = 0.0f; v2[3] = 0.0f
    in_chunk.columns[0]:set_i64(2, 103)
    in_chunk.columns[1]:set_vector(2, &(v2[0]), 4)

    in_chunk.num_rows = 3

    -- Query vector: [1.0, 0.0, 0.0, 0.0]
    var q : float[4]
    q[0] = 1.0f; q[1] = 0.0f; q[2] = 0.0f; q[3] = 0.0f

    -- Request top 2 nearest neighbors
    var knn_op : vknn.PhysicalVectorKNN
    knn_op:init(1, 0, 4, dist.METRIC_L2, 2, &(q[0]))
    knn_op:sink_chunk(&in_chunk)

    var out_chunk : DataChunk
    var out_types : types.DataType[2]
    out_types[0] = types.make_type(types.INT64, 0)
    out_types[1] = types.make_type(types.DOUBLE, 0)
    out_chunk:init(2, &(out_types[0]), 32)

    var count = knn_op:emit_results(&out_chunk)
    if count ~= 2 then
        C.printf("FAIL: expected 2 results, got %u\n", count)
        return 1
    end

    -- First neighbor must be id 101 with distance ~ 0.0
    var id0 = out_chunk.columns[0]:get_i64(0)
    var d0 = out_chunk.columns[1]:get_f64(0)
    if id0 ~= 101 or d0 > 0.001 then
        C.printf("FAIL: top neighbor expected 101, got %lld (dist=%f)\n", id0, d0)
        return 1
    end

    -- Second neighbor must be id 103 with distance < 0.2
    var id1 = out_chunk.columns[0]:get_i64(1)
    var d1 = out_chunk.columns[1]:get_f64(1)
    if id1 ~= 103 or d1 > 0.2 then
        C.printf("FAIL: second neighbor expected 103, got %lld (dist=%f)\n", id1, d1)
        return 1
    end

    in_chunk:destroy()
    out_chunk:destroy()
    knn_op:destroy()

    C.printf("PASS: PhysicalVectorKNN ranked top-2 nearest neighbors correctly\n")
    C.printf("=== ALL VECTOR KNN OPERATOR TESTS PASSED ===\n")
    return 0
end

local code = run_vector_knn_op_test()
if code ~= 0 then
    os.exit(1)
end
