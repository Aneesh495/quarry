-- test_simd_accuracy.t
-- Numerical precision, non-multiple-of-4 dimension tail handling,
-- and floating point edge case tests for Quarry SIMD kernels.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local simd = require("src.common.simd")
local dist = require("src.vector/distance")

terra run_simd_accuracy_tests() : int
    C.printf("=== Running Quarry SIMD Numerical Precision & Tail Edge Tests ===\n")

    -- Test 1: Orthogonal vectors (Dot Product == 0.0)
    var v1 : float[4]
    v1[0] = 1.0f; v1[1] = 0.0f; v1[2] = 0.0f; v1[3] = 0.0f
    var v2 : float[4]
    v2[0] = 0.0f; v2[1] = 1.0f; v2[2] = 0.0f; v2[3] = 0.0f

    var dot_ortho = dist.dot(&(v1[0]), &(v2[0]), 4)
    if C.fabsf(dot_ortho) > 1e-6f then
        C.printf("FAIL: orthogonal dot product expected 0.0, got %f\n", dot_ortho)
        return 1
    end
    C.printf("PASS: Test 1: Orthogonal vectors dot product evaluates to 0.0\n")

    -- Test 2: Identical vectors (L2 Distance == 0.0, Cosine Distance == 0.0)
    var v3 : float[4]
    v3[0] = 0.5f; v3[1] = 0.5f; v3[2] = 0.5f; v3[3] = 0.5f
    var d_l2 = dist.l2(&(v3[0]), &(v3[0]), 4)
    var d_cos = dist.cosine_dist(&(v3[0]), &(v3[0]), 4)

    if d_l2 > 1e-6f or d_cos > 1e-6f then
        C.printf("FAIL: identical vector distance mismatch (l2=%f, cos=%f)\n", d_l2, d_cos)
        return 1
    end
    C.printf("PASS: Test 2: Identical vector self-distance evaluates to 0.0\n")

    -- Test 3: Arbitrary odd and non-power-of-2 dimensions (tail handling)
    -- Testing dimensions: 1, 3, 5, 7, 13, 17, 33, 65
    var test_dims : uint32[8]
    test_dims[0] = 1
    test_dims[1] = 3
    test_dims[2] = 5
    test_dims[3] = 7
    test_dims[4] = 13
    test_dims[5] = 17
    test_dims[6] = 33
    test_dims[7] = 65

    for ti = 0, 8 do
        var dim = test_dims[ti]
        var buf_a = [&float](alloc.aligned_alloc(dim * sizeof(float), alloc.CACHE_LINE))
        var buf_b = [&float](alloc.aligned_alloc(dim * sizeof(float), alloc.CACHE_LINE))

        var ref_dot : double = 0.0
        var ref_l2_sq : double = 0.0

        for d = 0, dim do
            buf_a[d] = [float](d + 1) * 0.1f
            buf_b[d] = [float](d + 2) * 0.2f
            ref_dot = ref_dot + [double](buf_a[d]) * [double](buf_b[d])
            var diff = [double](buf_a[d]) - [double](buf_b[d])
            ref_l2_sq = ref_l2_sq + (diff * diff)
        end

        var kernel_dot = dist.dot(buf_a, buf_b, dim)
        var kernel_l2_sq = dist.l2_sq(buf_a, buf_b, dim)

        var err_dot = C.fabsf([float](ref_dot) - kernel_dot)
        var err_l2 = C.fabsf([float](ref_l2_sq) - kernel_l2_sq)

        if err_dot > 1e-3f or err_l2 > 1e-3f then
            C.printf("FAIL: dimension %u mismatch (err_dot=%f, err_l2=%f)\n", dim, err_dot, err_l2)
            alloc.aligned_free(buf_a)
            alloc.aligned_free(buf_b)
            return 1
        end

        alloc.aligned_free(buf_a)
        alloc.aligned_free(buf_b)
    end
    C.printf("PASS: Test 3: Tail loop scalar remainder across non-power-of-2 dimensions\n")

    -- Test 4: L1 Manhattan Distance
    var p1 : float[3]
    p1[0] = 1.0f; p1[1] = 2.0f; p1[2] = 3.0f
    var p2 : float[3]
    p2[0] = 4.0f; p2[1] = 6.0f; p2[2] = 8.0f
    -- |1-4| + |2-6| + |3-8| = 3 + 4 + 5 = 12
    var d_l1 = dist.l1(&(p1[0]), &(p2[0]), 3)
    if C.fabsf(d_l1 - 12.0f) > 1e-5f then
        C.printf("FAIL: L1 Manhattan distance expected 12.0, got %f\n", d_l1)
        return 1
    end
    C.printf("PASS: Test 4: L1 Manhattan distance numerical correctness (d=12.0)\n")

    C.printf("=== ALL SIMD ACCURACY TESTS PASSED (4/4) ===\n")
    return 0
end

local code = run_simd_accuracy_tests()
if code ~= 0 then
    os.exit(1)
end
