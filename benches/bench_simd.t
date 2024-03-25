-- bench_simd.t
-- Micro-benchmark comparing scalar floating point kernels
-- vs 4-wide SIMD vector intrinsics on 10,000,000 elements.

local C = require("src.common.c").C
local timer = require("src.common.timer")
local alloc = require("src.common.alloc")
local simd = require("src.common.simd")
local dist = require("src.vector/distance")

local N = 10000000

-- Scalar Dot Product
local terra scalar_dot(a: &float, b: &float, n: uint32) : float
    var sum : float = 0.0f
    for i = 0, n do
        sum = sum + a[i] * b[i]
    end
    return sum
end

-- Scalar L2 Distance Squared
local terra scalar_l2_sq(a: &float, b: &float, n: uint32) : float
    var sum : float = 0.0f
    for i = 0, n do
        var d = a[i] - b[i]
        sum = sum + d * d
    end
    return sum
end

local terra run_simd_bench() : int
    C.printf("=================================================================\n")
    C.printf("  QUARRY SIMD HARDWARE ACCELERATION BENCHMARK (%d Floats)\n", N)
    C.printf("=================================================================\n")

    var a = [&float](alloc.aligned_alloc(N * sizeof(float), alloc.CACHE_LINE))
    var b = [&float](alloc.aligned_alloc(N * sizeof(float), alloc.CACHE_LINE))

    for i = 0, N do
        a[i] = [float]((i % 100) + 1) * 0.01f
        b[i] = [float]((i % 50) + 1) * 0.02f
    end

    -- 1. Dot Product
    var sw : timer.Stopwatch
    sw:start()
    var s_dot = scalar_dot(a, b, N)
    sw:stop()
    var us_scalar_dot = sw:elapsed_us()

    sw:start()
    var v_dot = simd.dot_product_f32(a, b, N)
    sw:stop()
    var us_simd_dot = sw:elapsed_us()

    -- 2. L2 Distance
    sw:start()
    var s_l2 = scalar_l2_sq(a, b, N)
    sw:stop()
    var us_scalar_l2 = sw:elapsed_us()

    sw:start()
    var v_l2 = dist.l2_sq(a, b, N)
    sw:stop()
    var us_simd_l2 = sw:elapsed_us()

    var gflops_dot = (2.0 * [double](N)) / (us_simd_dot * 1000.0)
    var gflops_l2 = (3.0 * [double](N)) / (us_simd_l2 * 1000.0)

    var rel_diff_dot = C.fabsf(s_dot - v_dot) / s_dot
    var rel_diff_l2 = C.fabsf(s_l2 - v_l2) / s_l2

    var status_dot : &int8 = "MISMATCH"
    if rel_diff_dot < 0.01f then status_dot = "OK" end

    var status_l2 : &int8 = "MISMATCH"
    if rel_diff_l2 < 0.01f then status_l2 = "OK" end

    C.printf("Kernel      | Scalar (us) | SIMD (us) | Speedup | SIMD GFLOPS | Check\n")
    C.printf("------------|-------------|-----------|---------|-------------|------\n")
    C.printf("Dot Product | %11.1f | %9.1f | %6.2fx | %11.2f | %s\n",
        us_scalar_dot, us_simd_dot, us_scalar_dot / us_simd_dot, gflops_dot, status_dot)
    C.printf("L2 Distance | %11.1f | %9.1f | %6.2fx | %11.2f | %s\n",
        us_scalar_l2, us_simd_l2, us_scalar_l2 / us_simd_l2, gflops_l2, status_l2)
    C.printf("=================================================================\n")

    alloc.aligned_free(a)
    alloc.aligned_free(b)
    return 0
end

local code = run_simd_bench()
if code ~= 0 then os.exit(1) end
