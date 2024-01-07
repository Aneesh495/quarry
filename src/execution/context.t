-- Quarry execution context subsystem
-- Tracks thread state, memory quotas, and execution profiling metrics.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local timer = require("src.common.timer")

local ctx = {}

struct ExecutionMetrics {
    total_time_us: double,
    jit_compile_time_us: double,
    rows_scanned: uint64,
    rows_filtered: uint64,
    rows_produced: uint64,
    chunks_processed: uint32
}

struct ExecutionContext {
    arena: alloc.Arena,
    num_threads: uint32,
    stopwatch: timer.Stopwatch,
    metrics: ExecutionMetrics,
    use_jit: bool
}

terra ExecutionContext:init(num_threads: uint32, use_jit: bool)
    self.arena:init(131072) -- 128 KB initial block size
    if num_threads == 0 then
        self.num_threads = 4 -- default 4 worker threads
    else
        self.num_threads = num_threads
    end
    self.use_jit = use_jit
    C.memset(&(self.metrics), 0, sizeof(ExecutionMetrics))
end

terra ExecutionContext:destroy()
    self.arena:destroy()
end

terra ExecutionContext:start_timer()
    self.stopwatch:start()
end

terra ExecutionContext:stop_timer()
    self.stopwatch:stop()
    self.metrics.total_time_us = self.stopwatch:elapsed_us()
end

ctx.ExecutionMetrics = ExecutionMetrics
ctx.ExecutionContext = ExecutionContext
return ctx
