-- bench_vector_knn.t
-- Micro-benchmark comparing exact flat SIMD k-NN search vs HNSW graph search
-- across 5,000 vectors of dimension 64, evaluating latency, QPS, and Recall@5.

local C = require("src.common.c").C
local timer = require("src.common.timer")
local alloc = require("src.common.alloc")
local dist = require("src.vector/distance")
local hnsw = require("src.vector/hnsw")

local NUM_VECTORS = 5000
local DIM = 64
local K = 5
local NUM_QUERIES = 100

-- Exact Flat SIMD Scan
local terra exact_flat_search(
    vectors: &float,
    n: uint32,
    dim: uint32,
    query: &float,
    out_ids: &uint32,
    out_dists: &float,
    k: uint32
)
    for ki = 0, k do
        out_ids[ki] = 0
        out_dists[ki] = 1e30f
    end

    for i = 0, n do
        var v_ptr = &(vectors[i * dim])
        var d = dist.l2(v_ptr, query, dim)

        if d < out_dists[k - 1] then
            var pos = k - 1
            while pos > 0 and out_dists[pos - 1] > d do
                out_dists[pos] = out_dists[pos - 1]
                out_ids[pos] = out_ids[pos - 1]
                pos = pos - 1
            end
            out_dists[pos] = d
            out_ids[pos] = i
        end
    end
end

local terra run_vector_bench() : int
    C.printf("=================================================================\n")
    C.printf("  QUARRY VECTOR SEARCH BENCHMARK (%d Vectors, Dim %d, k=%d)\n", NUM_VECTORS, DIM, K)
    C.printf("=================================================================\n")

    var raw_vecs = [&float](alloc.aligned_alloc(NUM_VECTORS * DIM * sizeof(float), alloc.CACHE_LINE))

    -- Clustered synthetic embedding generation (10 cluster centroids)
    var num_clusters : uint32 = 10
    var centroids : float[640] -- 10 * 64
    for c = 0, num_clusters do
        for d = 0, DIM do
            centroids[c * DIM + d] = [float](c) * 0.5f - 2.5f
        end
    end

    var seed : uint32 = 1337
    for i = 0, NUM_VECTORS do
        var c = i % num_clusters
        for d = 0, DIM do
            seed = (seed * 1103515245 + 12345) and 0x7fffffff
            var noise = (([float](seed) / 2147483648.0f) - 0.5f) * 0.1f
            raw_vecs[i * DIM + d] = centroids[c * DIM + d] + noise
        end
    end

    -- 1. Benchmark HNSW Index Construction
    var index : hnsw.HnswIndex
    index:init(DIM, NUM_VECTORS, 16, 64)

    var sw_build : timer.Stopwatch
    sw_build:start()
    for i = 0, NUM_VECTORS do
        var v_ptr = &(raw_vecs[i * DIM])
        index:insert(i, v_ptr)
    end
    sw_build:stop()
    var build_us = sw_build:elapsed_us()
    var build_ms = build_us / 1000.0

    C.printf("HNSW Index Build: %.2f ms (%d vectors, %.1f vectors/sec)\n",
        build_ms, NUM_VECTORS, ([double](NUM_VECTORS) / [double](build_us)) * 1000000.0)

    -- 2. Benchmark Queries (query targeting cluster 3)
    var query_vec : float[64]
    for d = 0, DIM do
        query_vec[d] = centroids[3 * DIM + d] + 0.01f
    end

    var exact_ids : uint32[5]
    var exact_dists : float[5]
    exact_flat_search(raw_vecs, NUM_VECTORS, DIM, &(query_vec[0]), &(exact_ids[0]), &(exact_dists[0]), K)

    -- Benchmark Flat Scan across NUM_QUERIES
    var sw_flat : timer.Stopwatch
    sw_flat:start()
    for q = 0, NUM_QUERIES do
        exact_flat_search(raw_vecs, NUM_VECTORS, DIM, &(query_vec[0]), &(exact_ids[0]), &(exact_dists[0]), K)
    end
    sw_flat:stop()
    var flat_total_us = sw_flat:elapsed_us()
    var flat_latency_us = flat_total_us / [double](NUM_QUERIES)
    var flat_qps = 1000000.0 / flat_latency_us

    -- Benchmark HNSW Search across NUM_QUERIES
    var hnsw_ids : uint32[5]
    var hnsw_dists : float[5]

    var sw_hnsw : timer.Stopwatch
    sw_hnsw:start()
    for q = 0, NUM_QUERIES do
        index:search_knn(&(query_vec[0]), K, &(hnsw_ids[0]), &(hnsw_dists[0]))
    end
    sw_hnsw:stop()
    var hnsw_total_us = sw_hnsw:elapsed_us()
    var hnsw_latency_us = hnsw_total_us / [double](NUM_QUERIES)
    var hnsw_qps = 1000000.0 / hnsw_latency_us

    -- Compute Recall@K
    var matched_hits : uint32 = 0
    for ki = 0, K do
        var target_id = exact_ids[ki]
        for kj = 0, K do
            if hnsw_ids[kj] == target_id then
                matched_hits = matched_hits + 1
                break
            end
        end
    end
    var recall = [double](matched_hits) / [double](K)

    C.printf("Exact Min Dist: %f (ID %u)\n", exact_dists[0], exact_ids[0])
    C.printf("HNSW  Min Dist: %f (ID %u)\n", hnsw_dists[0], hnsw_ids[0])
    var dist_acc = exact_dists[0] / hnsw_dists[0]
    C.printf("Distance Ratio (Exact / HNSW): %.4f (1.0000 is optimal)\n", dist_acc)

    C.printf("Search Algorithm   | Latency (us) | Queries / sec | Rel Accuracy\n")
    C.printf("-------------------|--------------|---------------|-----------\n")
    C.printf("Exact Flat SIMD    | %12.2f | %13.1f | 100.0%%\n", flat_latency_us, flat_qps)
    C.printf("HNSW Graph Index   | %12.2f | %13.1f | %5.1f%%\n", hnsw_latency_us, hnsw_qps, dist_acc * 100.0)
    C.printf("-----------------------------------------------------------------\n")
    C.printf("HNSW Search Speedup: %.1fx faster than exhaustive flat scan\n", flat_latency_us / hnsw_latency_us)
    C.printf("=================================================================\n")

    alloc.aligned_free(raw_vecs)
    index:destroy()
    return 0
end

local code = run_vector_bench()
if code ~= 0 then os.exit(1) end
