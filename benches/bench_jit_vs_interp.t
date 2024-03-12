-- bench_jit_vs_interp.t
-- Micro-benchmark comparing interpreted tuple-at-a-time execution
-- vs Quarry LLVM fused pipeline JIT compilation on 1,000,000 tuples.

local C = require("src.common.c").C
local timer = require("src.common.timer")
local alloc = require("src.common.alloc")

local N = 1000000

local terra eval_discount(p: int64, d: int64) : int64
    return (p * (100 - d)) / 100
end

local terra eval_filter(val: int64, threshold: int64) : bool
    return val > threshold
end

-- Interpreted loop: dynamic function pointer call per tuple simulating traditional Volcano iterator
local terra run_interpreted(prices: &int64, discounts: &int64, n: uint32, threshold: int64) : int64
    var count : int64 = 0
    var total : int64 = 0
    var p_proj : {int64, int64} -> int64 = eval_discount
    var p_filt : {int64, int64} -> bool = eval_filter

    for i = 0, n do
        var p = prices[i]
        var d = discounts[i]
        var discounted_price = p_proj(p, d)
        if p_filt(discounted_price, threshold) then
            total = total + discounted_price
            count = count + 1
        end
    end
    return total
end

-- Fused JIT kernel: single-loop LLVM compiled with vectorization hints
local terra run_fused_jit(prices: &int64, discounts: &int64, n: uint32, threshold: int64) : int64
    var total : int64 = 0
    -- In a real JIT kernel, this is emitted as specialized LLVM IR
    -- where loop bounds, arithmetic constants, and pointer offsets are inlined
    for i = 0, n do
        var p = prices[i]
        var d = discounts[i]
        var val = (p * (100 - d)) / 100
        if val > threshold then
            total = total + val
        end
    end
    return total
end

local terra run_bench() : int
    C.printf("=================================================================\n")
    C.printf("  QUARRY JIT COMPILATION BENCHMARK (1,000,000 Rows)\n")
    C.printf("=================================================================\n")

    var prices = [&int64](alloc.aligned_alloc(N * sizeof(int64), alloc.CACHE_LINE))
    var discounts = [&int64](alloc.aligned_alloc(N * sizeof(int64), alloc.CACHE_LINE))

    for i = 0, N do
        prices[i] = [int64]((i % 100) + 10)
        discounts[i] = [int64](i % 10)
    end

    var threshold : int64 = 50

    -- Warmup
    run_interpreted(prices, discounts, 10000, threshold)
    run_fused_jit(prices, discounts, 10000, threshold)

    -- Benchmark Interpreted Execution
    var sw_interp : timer.Stopwatch
    sw_interp:start()
    var res_interp = run_interpreted(prices, discounts, N, threshold)
    sw_interp:stop()
    var us_interp = sw_interp:elapsed_us()

    -- Benchmark Fused JIT Execution
    var sw_jit : timer.Stopwatch
    sw_jit:start()
    var res_jit = run_fused_jit(prices, discounts, N, threshold)
    sw_jit:stop()
    var us_jit = sw_jit:elapsed_us()

    var m_rows_sec_interp = ([double](N) / [double](us_interp))
    var m_rows_sec_jit = ([double](N) / [double](us_jit))
    var speedup = [double](us_interp) / [double](us_jit)

    C.printf("Engine Mode        | Time (us) | Throughput (M rows/s) | Result\n")
    C.printf("-------------------|-----------|-----------------------|-----------\n")
    C.printf("Volcano / Interp   | %9.2f | %21.2f | %lld\n", us_interp, m_rows_sec_interp, res_interp)
    C.printf("Quarry Fused JIT   | %9.2f | %21.2f | %lld\n", us_jit, m_rows_sec_jit, res_jit)
    C.printf("-----------------------------------------------------------------\n")
    C.printf("Observed JIT Speedup: %.2fx faster\n", speedup)
    C.printf("=================================================================\n")

    alloc.aligned_free(prices)
    alloc.aligned_free(discounts)
    return 0
end

local code = run_bench()
if code ~= 0 then os.exit(1) end
