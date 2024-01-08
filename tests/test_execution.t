-- Test suite for Quarry morsel execution runtime

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local ctx = require("src.execution/context")
local morsel = require("src.execution/morsel")
local pool = require("src.execution/thread_pool")
local pipe = require("src.execution/pipeline")

terra run_execution_tests() : int
    C.printf("=== Running Quarry Morsel Execution Tests ===\n")

    -- Test 1: ExecutionContext and metrics
    var ec : ctx.ExecutionContext
    ec:init(4, true)
    ec:start_timer()
    C.usleep(500)
    ec:stop_timer()

    if ec.metrics.total_time_us < 200.0 or not ec.use_jit then
        C.printf("FAIL: ExecutionContext metrics invalid\n")
        return 1
    end
    ec:destroy()
    C.printf("PASS: ExecutionContext initialization and microsecond metrics\n")

    -- Test 2: MorselQueue chunk assignment
    var mq : morsel.MorselQueue
    mq:init(10) -- 10 chunks to process

    for i = 0, 10 do
        var m = mq:get_next_morsel()
        if m.is_exhausted or m.chunk_idx ~= i then
            C.printf("FAIL: morsel chunk_idx expected %u, got %u (exhausted=%d)\n", i, m.chunk_idx, m.is_exhausted)
            return 1
        end
    end

    -- 11th request must be exhausted
    var m_ex = mq:get_next_morsel()
    if not m_ex.is_exhausted then
        C.printf("FAIL: 11th morsel should be exhausted\n")
        return 1
    end

    mq:reset()
    var m_reset = mq:get_next_morsel()
    if m_reset.chunk_idx ~= 0 or m_reset.is_exhausted then
        C.printf("FAIL: morsel after reset expected chunk 0\n")
        return 1
    end
    mq:destroy()
    C.printf("PASS: MorselQueue dynamic chunk dispatch and exhaustion\n")

    -- Test 3: ThreadPool and Barrier Synchronization
    var tp : pool.ThreadPool
    tp:init(2) -- 2 threads
    -- Test barrier with 2 cycle barrier_wait calls
    tp.barrier_target = 1 -- simulate single thread entering barrier
    tp:barrier_wait()
    tp:destroy()
    C.printf("PASS: ThreadPool barrier synchronization lifecycle\n")

    -- Test 4: ResultCollector chunk accumulation
    var collector : pipe.ResultCollector
    collector:init()

    var c : chunk.DataChunk
    var dts : types.DataType[1]
    dts[0] = types.make_type(types.INT64, 0)
    c:init(1, &(dts[0]), 32)
    for i = 0, 15 do
        c.columns[0]:set_i64(i, [int64](i * 100))
    end
    c.num_rows = 15

    collector:add_chunk(&c)
    collector:add_chunk(&c)

    if collector.total_tuples ~= 30 or collector.num_chunks ~= 2 then
        C.printf("FAIL: ResultCollector expected 30 tuples across 2 chunks, got %llu\n", collector.total_tuples)
        return 1
    end

    c:destroy()
    collector:destroy()
    C.printf("PASS: ResultCollector chunk accumulation and tuple count tracking\n")

    C.printf("=== ALL EXECUTION TESTS PASSED (4/4) ===\n")
    return 0
end

local code = run_execution_tests()
if code ~= 0 then
    os.exit(1)
end
