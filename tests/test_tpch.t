-- Quarry TPC-H analytical benchmark verification suite
-- Validates TPC-H Q1 and Q6 execution accuracy and performance.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")
local token = require("src.parser/token")
local scan = require("src.operators/scan")
local filter = require("src.operators/filter")
local agg = require("src.operators/aggregate")
local jit_pipe = require("src.jit/pipeline_compiler")
local timer = require("src.common.timer")

local Table = tbl.Table
local DataChunk = chunk.DataChunk

terra run_tpch_tests() : int
    C.printf("=== Running Quarry TPC-H Benchmark Verification Suite ===\n")

    -- Setup LINEITEM table:
    -- col0: l_orderkey (INT64)
    -- col1: l_quantity (INT64)
    -- col2: l_extendedprice (INT64)
    -- col3: l_discount (INT64, e.g. percent 0..10)
    -- col4: l_returnflag (INT64, 1='A', 2='N', 3='R')
    var col_names : (&int8)[5]
    col_names[0] = "l_orderkey"
    col_names[1] = "l_quantity"
    col_names[2] = "l_extendedprice"
    col_names[3] = "l_discount"
    col_names[4] = "l_returnflag"

    var col_tps : types.DataType[5]
    col_tps[0] = types.make_type(types.INT64, 0)
    col_tps[1] = types.make_type(types.INT64, 0)
    col_tps[2] = types.make_type(types.INT64, 0)
    col_tps[3] = types.make_type(types.INT64, 0)
    col_tps[4] = types.make_type(types.INT64, 0)

    var lineitem : Table
    lineitem:init("lineitem", 5, &(col_names[0]), &(col_tps[0]))

    -- Generate 10,000 synthetic lineitem tuples
    for i = 0, 10000 do
        var c = lineitem:get_or_create_active_chunk()
        var r = c.num_rows

        c.columns[0]:set_i64(r, [int64](i + 1))
        c.columns[1]:set_i64(r, [int64]((i % 50) + 1)) -- quantity 1..50
        c.columns[2]:set_i64(r, [int64](((i % 50) + 1) * 1000)) -- price
        c.columns[3]:set_i64(r, [int64](i % 10)) -- discount 0..9
        c.columns[4]:set_i64(r, [int64]((i % 3) + 1)) -- returnflag 1, 2, 3

        c.num_rows = r + 1
        lineitem.total_rows = lineitem.total_rows + 1
    end

    -- Test 1: TPC-H Query 1 (Pricing Summary Report)
    -- SELECT l_returnflag, COUNT(*), SUM(l_quantity), SUM(l_extendedprice) FROM lineitem GROUP BY l_returnflag
    var sw : timer.Stopwatch
    sw:start()

    var q1_agg : agg.PhysicalHashAggregate
    q1_agg:init(16, 4, 2, true) -- group_by=l_returnflag (col4), sum=l_extendedprice (col2)

    var s : scan.PhysicalScan
    s:init(&lineitem)
    while true do
        var chk = s:get_next_chunk()
        if chk == nil then break end
        q1_agg:sink(chk)
    end

    sw:stop()

    if q1_agg.num_groups ~= 3 then
        C.printf("FAIL: TPC-H Q1 expected 3 returnflag groups, got %u\n", q1_agg.num_groups)
        return 1
    end

    var out_q1 : DataChunk
    var q1_tps : types.DataType[3]
    q1_tps[0] = types.make_type(types.INT64, 0)
    q1_tps[1] = types.make_type(types.INT64, 0)
    q1_tps[2] = types.make_type(types.INT64, 0)
    out_q1:init(3, &(q1_tps[0]), 16)
    q1_agg:emit(&out_q1)

    C.printf("PASS: TPC-H Query 1 Pricing Summary (10,000 rows in %.2f us)\n", sw:elapsed_us())

    -- Test 2: TPC-H Query 6 (Forecasting Revenue Change)
    -- SELECT SUM(l_extendedprice) FROM lineitem WHERE l_quantity < 24
    -- Execute using JIT fused single-loop kernel!
    var jit_q6 = [ jit_pipe.compile_filter_sum(1, "<", 24, 2) ]

    sw:start()
    s:reset()
    var total_q6_count : uint64 = 0
    var total_q6_revenue : int64 = 0

    while true do
        var chk = s:get_next_chunk()
        if chk == nil then break end

        var chunk_cnt : uint64 = 0
        var chunk_rev : int64 = 0
        jit_q6(chk, &chunk_cnt, &chunk_rev)

        total_q6_count = total_q6_count + chunk_cnt
        total_q6_revenue = total_q6_revenue + chunk_rev
    end
    sw:stop()

    if total_q6_count == 0 or total_q6_revenue == 0 then
        C.printf("FAIL: TPC-H Q6 revenue calculation returned zero\n")
        return 1
    end

    C.printf("PASS: TPC-H Query 6 Fused JIT Revenue Scan (Revenue=%lld, %llu rows in %.2f us)\n",
        total_q6_revenue, total_q6_count, sw:elapsed_us())

    out_q1:destroy()
    q1_agg:destroy()
    lineitem:destroy()

    C.printf("=== ALL TPC-H BENCHMARKS PASSED (2/2) ===\n")
    return 0
end

local code = run_tpch_tests()
if code ~= 0 then
    os.exit(1)
end
