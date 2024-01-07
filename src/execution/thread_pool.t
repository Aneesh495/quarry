-- Quarry POSIX thread pool subsystem
-- Executes morsel pipelines concurrently with barrier synchronization.

local C = require("src.common.c").C

local pool = {}

pool.MAX_WORKERS = 16

struct Task {
    fn_ptr: &(&opaque -> &opaque),
    arg: &opaque
}

struct ThreadPool {
    num_threads: uint32,
    threads: C.pthread_t[16],
    is_running: bool,
    queue_mutex: C.pthread_mutex_t,
    queue_cond: C.pthread_cond_t,
    barrier_mutex: C.pthread_mutex_t,
    barrier_cond: C.pthread_cond_t,
    barrier_target: uint32,
    barrier_count: uint32,
    barrier_cycle: uint32
}

terra ThreadPool:init(num_threads: uint32)
    var n = num_threads
    if n > 16 then n = 16 end
    if n == 0 then n = 1 end
    self.num_threads = n
    self.is_running = true

    C.pthread_mutex_init(&(self.queue_mutex), nil)
    C.pthread_cond_init(&(self.queue_cond), nil)

    C.pthread_mutex_init(&(self.barrier_mutex), nil)
    C.pthread_cond_init(&(self.barrier_cond), nil)
    self.barrier_target = n
    self.barrier_count = 0
    self.barrier_cycle = 0
end

terra ThreadPool:destroy()
    self.is_running = false
    C.pthread_mutex_destroy(&(self.queue_mutex))
    C.pthread_cond_destroy(&(self.queue_cond))
    C.pthread_mutex_destroy(&(self.barrier_mutex))
    C.pthread_cond_destroy(&(self.barrier_cond))
end

-- Barrier synchronization across all worker threads
terra ThreadPool:barrier_wait()
    C.pthread_mutex_lock(&(self.barrier_mutex))
    var cycle = self.barrier_cycle
    self.barrier_count = self.barrier_count + 1

    if self.barrier_count >= self.barrier_target then
        self.barrier_cycle = self.barrier_cycle + 1
        self.barrier_count = 0
        C.pthread_cond_broadcast(&(self.barrier_cond))
    else
        while cycle == self.barrier_cycle do
            C.pthread_cond_wait(&(self.barrier_cond), &(self.barrier_mutex))
        end
    end
    C.pthread_mutex_unlock(&(self.barrier_mutex))
end

pool.ThreadPool = ThreadPool
return pool
