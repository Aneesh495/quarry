-- Test suite for Quarry JIT compilation and pipeline fusion

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local jit_pipe = require("src.jit/pipeline_compiler")
local cache = require("src.jit/kernel_cache")

local DataChunk = chunk.DataChunk

-- Compile JIT kernels at meta-time
local filter_sum_kernel = jit_pipe.compile_filter_sum(0, ">", 50, 1)
local filter_proj_kernel = jit_pipe.compile_filter_project(0, ">", 20, 1.5)

terra run_jit_tests() : int
    C.printf("=== Running Quarry JIT Query Compilation Tests ===\n")

    -- Setup chunk with 100 rows: col0 = id (0..99), col1 = price (id * 10)
    var c : DataChunk
    var dts : types.DataType[2]
    dts[0] = types.make_type(types.INT64, 0)
    dts[1] = types.make_type(types.INT64, 0)
    c:init(2, &(dts[0]), 128)

    for i = 0, 100 do
        c.columns[0]:set_i64(i, [int64](i))
        c.columns[1]:set_i64(i, [int64](i * 10))
    end
    c.num_rows = 100

    -- Test 1: JIT Fused Filter + Sum Aggregate (id > 50, SUM(price))
    var out_cnt : uint64 = 0
    var out_sum : int64 = 0
    filter_sum_kernel(&c, &out_cnt, &out_sum)

    -- Elements > 50 are 51..99 (49 elements).
    -- Sum of 51..99 = (51+99)*49 / 2 = 150 * 49 / 2 = 3675.
    -- Price is 10x = 36750.
    if out_cnt ~= 49 or out_sum ~= 36750 then
        C.printf("FAIL: JIT filter-sum mismatch (cnt=%llu, sum=%lld, expected cnt=49, sum=36750)\n", out_cnt, out_sum)
        return 1
    end
    C.printf("PASS: JIT Fused single-loop filter and sum aggregation kernel\n")

    -- Test 2: JIT Fused Filter + Project (id > 20, col1 = id * 1.5)
    var out_c : DataChunk
    var out_dts : types.DataType[2]
    out_dts[0] = types.make_type(types.INT64, 0)
    out_dts[1] = types.make_type(types.DOUBLE, 0)
    out_c:init(2, &(out_dts[0]), 128)

    var matched = filter_proj_kernel(&c, &out_c)
    -- id > 20 has 79 elements (21..99)
    if matched ~= 79 or out_c.num_rows ~= 79 then
        C.printf("FAIL: JIT filter-project matched count expected 79, got %u\n", matched)
        return 1
    end

    -- First matched row: id=21, scaled = 21 * 1.5 = 31.5
    var v0 = out_c.columns[0]:get_i64(0)
    var v1 = out_c.columns[1]:get_f64(0)
    if v0 ~= 21 or C.fabs(v1 - 31.5) > 0.001 then
        C.printf("FAIL: JIT projected values mismatch (v0=%lld, v1=%f)\n", v0, v1)
        return 1
    end
    C.printf("PASS: JIT Fused filter and in-register expression projection kernel\n")

    -- Test 3: Kernel Cache hit/miss tracking
    var kcache : cache.KernelCache
    kcache:init()
    var h1 : uint64 = 0xABCD1234ULL

    var cached_ptr = kcache:lookup(h1)
    if cached_ptr ~= nil or kcache.misses ~= 1 then
        C.printf("FAIL: initial lookup should be miss\n")
        return 1
    end

    kcache:insert(h1, [&opaque](filter_sum_kernel))
    var hit_ptr = kcache:lookup(h1)
    if hit_ptr == nil or kcache.hits ~= 1 then
        C.printf("FAIL: second lookup should be hit\n")
        return 1
    end
    C.printf("PASS: JIT Kernel cache hit/miss amortizing LLVM compilation\n")

    c:destroy()
    out_c:destroy()
    C.printf("=== ALL JIT TESTS PASSED (3/3) ===\n")
    return 0
end

local code = run_jit_tests()
if code ~= 0 then
    os.exit(1)
end
