-- test_concurrency.t
-- High contention stress test for multi-threaded MorselQueue dispatch
-- Spawns worker threads to process 5,000 chunks concurrently.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local morsel = require("src.execution/morsel")

local NUM_CHUNKS = 5000
local NUM_WORKERS = 4

struct WorkerContext {
    queue: &morsel.MorselQueue,
    claimed_flags: &uint8,
    worker_id: uint32,
    processed_count: uint32
}

-- Worker thread function
local terra worker_routine(arg: &opaque) : &opaque
    var ctx = [&WorkerContext](arg)
    while true do
        var m = ctx.queue:get_next_morsel()
        if m.is_exhausted then
            break
        end

        var idx = m.chunk_idx
        -- Mark as claimed (check for race condition / duplicate claim)
        if ctx.claimed_flags[idx] ~= 0 then
            C.printf("RACE DETECTED: Chunk %u was claimed more than once!\n", idx)
        end
        ctx.claimed_flags[idx] = 1
        ctx.processed_count = ctx.processed_count + 1
    end
    return nil
end

terra run_concurrency_stress_test() : int
    C.printf("=== Running Quarry Concurrency & Thread Contention Stress Test ===\n")
    C.printf("Spawning %d worker threads to process %d morsels...\n", NUM_WORKERS, NUM_CHUNKS)

    var queue : morsel.MorselQueue
    queue:init(NUM_CHUNKS)

    var claimed = [&uint8](alloc.aligned_alloc(NUM_CHUNKS * sizeof(uint8), alloc.CACHE_LINE))
    C.memset(claimed, 0, NUM_CHUNKS * sizeof(uint8))

    var contexts : WorkerContext[4]
    var threads : C.pthread_t[4]

    for w = 0, NUM_WORKERS do
        contexts[w].queue = &queue
        contexts[w].claimed_flags = claimed
        contexts[w].worker_id = w
        contexts[w].processed_count = 0

        var err = C.pthread_create(&(threads[w]), nil, worker_routine, &(contexts[w]))
        if err ~= 0 then
            C.printf("FAIL: failed to spawn worker thread %u\n", w)
            return 1
        end
    end

    -- Join threads
    for w = 0, NUM_WORKERS do
        C.pthread_join(threads[w], nil)
    end

    -- Verification pass
    var total_processed : uint32 = 0
    for w = 0, NUM_WORKERS do
        C.printf("Worker %u processed %u morsels\n", w, contexts[w].processed_count)
        total_processed = total_processed + contexts[w].processed_count
    end

    if total_processed ~= NUM_CHUNKS then
        C.printf("FAIL: expected %u processed chunks, got %u\n", NUM_CHUNKS, total_processed)
        return 1
    end

    for i = 0, NUM_CHUNKS do
        if claimed[i] ~= 1 then
            C.printf("FAIL: chunk %u was never claimed!\n", i)
            return 1
        end
    end

    queue:destroy()
    alloc.aligned_free(claimed)

    C.printf("PASS: Zero race conditions detected across %u concurrent morsel dispatches\n", NUM_CHUNKS)
    C.printf("=== CONCURRENCY STRESS TESTS PASSED (1/1) ===\n")
    return 0
end

local code = run_concurrency_stress_test()
if code ~= 0 then
    os.exit(1)
end
