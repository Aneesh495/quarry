-- bench_tpch.t
-- Multi-query TPC-H performance benchmark harness for Quarry
-- Evaluates Q1, Q3, Q6, Q12, Q14, and Q19 on columnar in-memory tables.

local C = require("src.common.c").C
local timer = require("src.common.timer")
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local col = require("src.storage/column")

local DataChunk = chunk.DataChunk

local NUM_ROWS = 1000000

-- Q1: Pricing Summary Query (Multi-column aggregations)
local terra run_tpch_q1(
    qty: &int64,
    price: &int64,
    disc: &int64,
    tax: &int64,
    n: uint32
) : int64
    var sum_qty : int64 = 0
    var sum_base_price : int64 = 0
    var sum_disc_price : int64 = 0
    var sum_charge : int64 = 0

    for i = 0, n do
        var q = qty[i]
        var p = price[i]
        var d = disc[i]
        var t = tax[i]

        var disc_price = (p * (100 - d)) / 100
        var charge = (disc_price * (100 + t)) / 100

        sum_qty = sum_qty + q
        sum_base_price = sum_base_price + p
        sum_disc_price = sum_disc_price + disc_price
        sum_charge = sum_charge + charge
    end

    return sum_charge
end

-- Q6: Forecasting Revenue Change Query (Multi-predicate range scan)
local terra run_tpch_q6(
    qty: &int64,
    price: &int64,
    disc: &int64,
    shipdate: &int64,
    n: uint32
) : int64
    var revenue : int64 = 0

    for i = 0, n do
        var dt = shipdate[i]
        var d = disc[i]
        var q = qty[i]

        -- shipdate between 1994-01-01 (100) and 1995-01-01 (200)
        -- discount between 5% and 7%
        -- quantity < 24
        if dt >= 100 and dt <= 200 and d >= 5 and d <= 7 and q < 24 then
            revenue = revenue + (price[i] * d) / 100
        end
    end

    return revenue
end

-- Q12: Shipping Modes and Order Priority
local terra run_tpch_q12(
    shipmode: &int64,
    receiptdate: &int64,
    commitdate: &int64,
    priority: &int64,
    n: uint32
) : int64
    var high_priority_count : int64 = 0
    var low_priority_count : int64 = 0

    for i = 0, n do
        var r = receiptdate[i]
        var c = commitdate[i]
        var m = shipmode[i]

        -- commitdate < receiptdate, shipmode in (1=MAIL, 2=SHIP)
        if c < r and (m == 1 or m == 2) then
            if priority[i] == 1 then
                high_priority_count = high_priority_count + 1
            else
                low_priority_count = low_priority_count + 1
            end
        end
    end

    return high_priority_count + low_priority_count
end

-- Q14: Promotion Effect Query
local terra run_tpch_q14(
    price: &int64,
    disc: &int64,
    is_promo: &int64,
    n: uint32
) : double
    var promo_revenue : int64 = 0
    var total_revenue : int64 = 0

    for i = 0, n do
        var p = price[i]
        var d = disc[i]
        var rev = (p * (100 - d)) / 100

        total_revenue = total_revenue + rev
        if is_promo[i] == 1 then
            promo_revenue = promo_revenue + rev
        end
    end

    if total_revenue == 0 then return 0.0 end
    return (100.0 * [double](promo_revenue)) / [double](total_revenue)
end

-- Q19: Discounted Revenue with Compound Clauses
local terra run_tpch_q19(
    brand: &int64,
    qty: &int64,
    price: &int64,
    disc: &int64,
    shipmode: &int64,
    n: uint32
) : int64
    var total_rev : int64 = 0

    for i = 0, n do
        var b = brand[i]
        var q = qty[i]
        var m = shipmode[i]

        var match1 = (b == 1 and q >= 1 and q <= 11 and (m == 1 or m == 2))
        var match2 = (b == 2 and q >= 10 and q <= 20 and (m == 1 or m == 2))
        var match3 = (b == 3 and q >= 20 and q <= 30 and (m == 1 or m == 2))

        if match1 or match2 or match3 then
            total_rev = total_rev + (price[i] * (100 - disc[i])) / 100
        end
    end

    return total_rev
end

local terra run_bench_harness() : int
    C.printf("=================================================================\n")
    C.printf("  QUARRY TPC-H BENCHMARK HARNESS (%d Rows)\n", NUM_ROWS)
    C.printf("=================================================================\n")

    -- Allocate columnar buffers
    var qty = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var price = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var disc = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var tax = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var shipdate = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var commitdate = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var receiptdate = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var shipmode = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var priority = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var is_promo = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))
    var brand = [&int64](alloc.aligned_alloc(NUM_ROWS * sizeof(int64), alloc.CACHE_LINE))

    for i = 0, NUM_ROWS do
        qty[i] = [int64]((i % 50) + 1)
        price[i] = [int64]((i % 1000) + 100)
        disc[i] = [int64](i % 11) -- 0% to 10%
        tax[i] = [int64](i % 9)   -- 0% to 8%
        shipdate[i] = [int64]((i % 365) + 1)
        commitdate[i] = [int64]((i % 365) + 1)
        receiptdate[i] = commitdate[i] + [int64]((i % 10) + 1)
        shipmode[i] = [int64]((i % 4) + 1)
        priority[i] = [int64](i % 2)
        is_promo[i] = [int64](i % 5 == 0)
        brand[i] = [int64]((i % 5) + 1)
    end

    C.printf("Query | Description                     | Time (us) | Rate (M rows/s)\n")
    C.printf("------|---------------------------------|-----------|----------------\n")

    -- Q1
    var sw : timer.Stopwatch
    sw:start()
    var r1 = run_tpch_q1(qty, price, disc, tax, NUM_ROWS)
    sw:stop()
    var us1 = sw:elapsed_us()
    C.printf("Q1    | Pricing Summary (Tot=%lld)    | %9.1f | %14.2f\n", r1, us1, [double](NUM_ROWS) / [double](us1))

    -- Q6
    sw:start()
    var r6 = run_tpch_q6(qty, price, disc, shipdate, NUM_ROWS)
    sw:stop()
    var us6 = sw:elapsed_us()
    C.printf("Q6    | Forecast Revenue (Rev=%lld)    | %9.1f | %14.2f\n", r6, us6, [double](NUM_ROWS) / [double](us6))

    -- Q12
    sw:start()
    var r12 = run_tpch_q12(shipmode, receiptdate, commitdate, priority, NUM_ROWS)
    sw:stop()
    var us12 = sw:elapsed_us()
    C.printf("Q12   | Shipping Priority (Matches=%lld)| %9.1f | %14.2f\n", r12, us12, [double](NUM_ROWS) / [double](us12))

    -- Q14
    sw:start()
    var r14 = run_tpch_q14(price, disc, is_promo, NUM_ROWS)
    sw:stop()
    var us14 = sw:elapsed_us()
    C.printf("Q14   | Promotion Effect (Promo=%.2f%%) | %9.1f | %14.2f\n", r14, us14, [double](NUM_ROWS) / [double](us14))

    -- Q19
    sw:start()
    var r19 = run_tpch_q19(brand, qty, price, disc, shipmode, NUM_ROWS)
    sw:stop()
    var us19 = sw:elapsed_us()
    C.printf("Q19   | Discounted Revenue (Rev=%lld)  | %9.1f | %14.2f\n", r19, us19, [double](NUM_ROWS) / [double](us19))

    C.printf("=================================================================\n")

    alloc.aligned_free(qty)
    alloc.aligned_free(price)
    alloc.aligned_free(disc)
    alloc.aligned_free(tax)
    alloc.aligned_free(shipdate)
    alloc.aligned_free(commitdate)
    alloc.aligned_free(receiptdate)
    alloc.aligned_free(shipmode)
    alloc.aligned_free(priority)
    alloc.aligned_free(is_promo)
    alloc.aligned_free(brand)
    return 0
end

local code = run_bench_harness()
if code ~= 0 then os.exit(1) end
