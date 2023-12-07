-- Test suite for Quarry columnar types, values, and vector math

local C = require("src.common.c").C
local types = require("src.types.type")
local value = require("src.types.value")
local vec = require("src.types.vector")

terra run_types_tests() : int
    C.printf("=== Running Quarry Types, Values, and Vector Tests ===\n")

    -- Test 1: DataType definitions and properties
    var t_int = types.make_type(types.INT32, 0)
    if not t_int:is_numeric() or not t_int:is_integer() or t_int.byte_width ~= 4 then
        C.printf("FAIL: DataType INT32 check failed\n")
        return 1
    end
    var t_vec = types.make_type(types.VECTOR_F32, 128)
    if not t_vec:is_vector() or t_vec.byte_width ~= 512 then
        C.printf("FAIL: DataType VECTOR_F32 128-dim byte_width expected 512, got %u\n", t_vec.byte_width)
        return 1
    end
    C.printf("PASS: Logical and physical DataType properties\n")

    -- Test 2: Value construction, formatting, and nulls
    var v_null = value.make_null(types.INT64)
    if not v_null.is_null then
        C.printf("FAIL: make_null is not null\n")
        return 1
    end
    var buf : int8[128]
    v_null:format(&(buf[0]), 128)
    if C.strcmp(&(buf[0]), "NULL") ~= 0 then
        C.printf("FAIL: null format expected 'NULL', got '%s'\n", &(buf[0]))
        return 1
    end

    var v_int = value.make_i64(42)
    v_int:format(&(buf[0]), 128)
    if C.strcmp(&(buf[0]), "42") ~= 0 then
        C.printf("FAIL: int format expected '42', got '%s'\n", &(buf[0]))
        return 1
    end

    var v_str = value.make_string("quarry_jit")
    v_str:format(&(buf[0]), 128)
    if C.strcmp(&(buf[0]), "quarry_jit") ~= 0 then
        C.printf("FAIL: string format expected 'quarry_jit', got '%s'\n", &(buf[0]))
        return 1
    end
    C.printf("PASS: Scalar Value tagged union construction and formatting\n")

    -- Test 3: Value comparisons
    var v1 = value.make_i64(100)
    var v2 = value.make_i64(200)
    var v3 = value.make_i64(100)
    if v1:compare(&v2) >= 0 or v2:compare(&v1) <= 0 or not v1:equals(&v3) then
        C.printf("FAIL: Value integer comparison failed\n")
        return 1
    end

    var s1 = value.make_string("alpha")
    var s2 = value.make_string("beta")
    if s1:compare(&s2) >= 0 then
        C.printf("FAIL: Value string comparison failed\n")
        return 1
    end
    C.printf("PASS: Value equality and ordered comparison\n")

    -- Test 4: Dense Vector creation and L2 norm
    var v_dim4 : vec.DenseVector
    v_dim4:init(4)
    var raw_data : float[4]
    raw_data[0] = 1.0f; raw_data[1] = 2.0f; raw_data[2] = 2.0f; raw_data[3] = 4.0f
    v_dim4:copy_from(&(raw_data[0]), 4)

    -- norm = sqrt(1 + 4 + 4 + 16) = sqrt(25) = 5.0
    var norm = v_dim4:l2_norm()
    if C.fabsf(norm - 5.0f) > 0.001f then
        C.printf("FAIL: vector L2 norm expected 5.0, got %f\n", norm)
        return 1
    end
    v_dim4:normalize()
    var unit_norm = v_dim4:l2_norm()
    if C.fabsf(unit_norm - 1.0f) > 0.001f then
        C.printf("FAIL: normalized vector norm expected 1.0, got %f\n", unit_norm)
        return 1
    end
    v_dim4:destroy()
    C.printf("PASS: DenseVector L2 norm and unit sphere normalization\n")

    -- Test 5: Cosine Similarity and L2 Distance
    var va : vec.DenseVector
    var vb : vec.DenseVector
    va:init(4); vb:init(4)
    var data_a : float[4]
    var data_b : float[4]
    data_a[0] = 1.0f; data_a[1] = 0.0f; data_a[2] = 1.0f; data_a[3] = 0.0f
    data_b[0] = 0.0f; data_b[1] = 1.0f; data_b[2] = 0.0f; data_b[3] = 1.0f
    va:copy_from(&(data_a[0]), 4)
    vb:copy_from(&(data_b[0]), 4)

    -- Orthogonal vectors: cosine similarity should be 0.0
    var cos_sim = va:cosine_similarity(&vb)
    if C.fabsf(cos_sim) > 0.001f then
        C.printf("FAIL: orthogonal cosine similarity expected 0.0, got %f\n", cos_sim)
        return 1
    end

    -- Identical vectors: cosine similarity should be 1.0
    var self_sim = va:cosine_similarity(&va)
    if C.fabsf(self_sim - 1.0f) > 0.001f then
        C.printf("FAIL: identical cosine similarity expected 1.0, got %f\n", self_sim)
        return 1
    end

    -- Squared L2 distance between [1,0,1,0] and [0,1,0,1] is 1 + 1 + 1 + 1 = 4.0
    var l2_sq = va:l2_distance_sq(&vb)
    if C.fabsf(l2_sq - 4.0f) > 0.001f then
        C.printf("FAIL: L2 distance squared expected 4.0, got %f\n", l2_sq)
        return 1
    end

    va:destroy()
    vb:destroy()
    C.printf("PASS: Cosine similarity and Euclidean distance kernels\n")

    C.printf("=== ALL TYPES TESTS PASSED (5/5) ===\n")
    return 0
end

local code = run_types_tests()
if code ~= 0 then
    os.exit(1)
end
