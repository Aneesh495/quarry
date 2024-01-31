-- Test suite for Quarry vector similarity and index subsystem

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local dist = require("src.vector/distance")
local hnsw = require("src.vector/hnsw")
local ivf = require("src.vector/ivf")
local hybrid = require("src.vector/hybrid")

local DataChunk = chunk.DataChunk

terra run_vector_tests() : int
    C.printf("=== Running Quarry Vector Index and Similarity Tests ===\n")

    -- Test 1: Distance kernels
    var v1 : float[4]
    var v2 : float[4]
    v1[0] = 1.0f; v1[1] = 0.0f; v1[2] = 0.0f; v1[3] = 0.0f
    v2[0] = 0.0f; v2[1] = 1.0f; v2[2] = 0.0f; v2[3] = 0.0f

    -- Orthogonal vectors have dot=0, cosine distance = 1.0, L2 distance = sqrt(2) = 1.4142
    var d_dot = dist.dot(&(v1[0]), &(v2[0]), 4)
    var d_cos = dist.cosine_dist(&(v1[0]), &(v2[0]), 4)
    var d_l2 = dist.l2(&(v1[0]), &(v2[0]), 4)

    if C.fabsf(d_dot) > 0.001f or C.fabsf(d_cos - 1.0f) > 0.001f or C.fabsf(d_l2 - 1.4142f) > 0.01f then
        C.printf("FAIL: vector distance mismatch (dot=%f, cos=%f, l2=%f)\n", d_dot, d_cos, d_l2)
        return 1
    end
    C.printf("PASS: SIMD Cosine, Dot product, and Euclidean distance kernels\n")

    -- Test 2: HNSW Index construction and k-NN search
    var idx : hnsw.HnswIndex
    idx:init(4, 32, 16, 32)

    var points : (float[4])[5]
    -- Point 0: [1, 0, 0, 0]
    points[0][0] = 1.0f; points[0][1] = 0.0f; points[0][2] = 0.0f; points[0][3] = 0.0f
    -- Point 1: [0.9, 0.1, 0, 0] (very close to Point 0)
    points[1][0] = 0.9f; points[1][1] = 0.1f; points[1][2] = 0.0f; points[1][3] = 0.0f
    -- Point 2: [0, 1, 0, 0]
    points[2][0] = 0.0f; points[2][1] = 1.0f; points[2][2] = 0.0f; points[2][3] = 0.0f
    -- Point 3: [0, 0, 1, 0]
    points[3][0] = 0.0f; points[3][1] = 0.0f; points[3][2] = 1.0f; points[3][3] = 0.0f
    -- Point 4: [0, 0, 0, 1]
    points[4][0] = 0.0f; points[4][1] = 0.0f; points[4][2] = 0.0f; points[4][3] = 1.0f

    for i = 0, 5 do
        idx:insert(i, &(points[i][0]))
    end

    if idx.count ~= 5 then
        C.printf("FAIL: HNSW count expected 5, got %u\n", idx.count)
        return 1
    end

    -- Query with [1, 0, 0, 0] looking for top-2 nearest neighbors
    var q : float[4]
    q[0] = 1.0f; q[1] = 0.0f; q[2] = 0.0f; q[3] = 0.0f
    var out_ids : uint32[2]
    var out_dists : float[2]
    var found = idx:search_knn(&(q[0]), 2, &(out_ids[0]), &(out_dists[0]))

    if found ~= 2 or out_ids[0] ~= 0 or out_ids[1] ~= 1 then
        C.printf("FAIL: HNSW k-NN search expected [0, 1], got [%u, %u]\n", out_ids[0], out_ids[1])
        return 1
    end
    idx:destroy()
    C.printf("PASS: HNSW multi-layer proximity graph insertion and k-NN search\n")

    -- Test 3: IVF Index cluster training and posting list assignment
    var ivf_idx : ivf.IvfIndex
    ivf_idx:init(4, 2, 32)
    ivf_idx:train_centroids(&(points[0][0]), 2)

    for i = 0, 5 do
        ivf_idx:add_vector(i, &(points[i][0]))
    end

    if ivf_idx.total_vectors ~= 5 then
        C.printf("FAIL: IVF total_vectors expected 5, got %u\n", ivf_idx.total_vectors)
        return 1
    end
    ivf_idx:destroy()
    C.printf("PASS: IVF Inverted File Index centroid training and vector routing\n")

    -- Test 4: Hybrid Relational + Vector Search
    var h_exec : hybrid.HybridQueryExecutor
    h_exec:init(4, dist.METRIC_L2)

    var c : DataChunk
    var dts : types.DataType[2]
    dts[0] = types.make_type(types.INT64, 0) -- id
    dts[1] = types.make_type(types.VECTOR_F32, 4) -- embedding
    c:init(2, &(dts[0]), 16)

    for i = 0, 5 do
        c.columns[0]:set_i64(i, [int64](i))
        c.columns[1]:set_vector(i, &(points[i][0]), 4)
    end
    c.num_rows = 5

    -- Mask to only even rows (0, 2, 4)
    var sel : uint32[3]
    sel[0] = 0; sel[1] = 2; sel[2] = 4
    c:set_selection(&(sel[0]), 3)

    var top_ids : uint32[2]
    var top_dists : float[2]
    var ranked = h_exec:rank_chunk(&c, 1, &(q[0]), 2, &(top_ids[0]), &(top_dists[0]))

    if ranked ~= 2 or top_ids[0] ~= 0 then
        C.printf("FAIL: hybrid rank_chunk expected top match 0, got %u\n", top_ids[0])
        return 1
    end
    c:destroy()
    C.printf("PASS: Hybrid relational selection and vector distance ranking\n")

    C.printf("=== ALL VECTOR TESTS PASSED (4/4) ===\n")
    return 0
end

local code = run_vector_tests()
if code ~= 0 then
    os.exit(1)
end
