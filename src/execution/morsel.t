-- Quarry morsel-driven execution queue
-- Dynamically partitions table chunks into lock-free morsels across worker threads.

local C = require("src.common.c").C

local morsel = {}

struct Morsel {
    chunk_idx: uint32,
    num_rows: uint32,
    is_exhausted: bool
}

struct MorselQueue {
    total_chunks: uint32,
    current_chunk: uint32,
    mutex: C.pthread_mutex_t
}

terra MorselQueue:init(total_chunks: uint32)
    self.total_chunks = total_chunks
    self.current_chunk = 0
    C.pthread_mutex_init(&(self.mutex), nil)
end

terra MorselQueue:destroy()
    C.pthread_mutex_destroy(&(self.mutex))
end

terra MorselQueue:get_next_morsel() : Morsel
    C.pthread_mutex_lock(&(self.mutex))
    var m : Morsel
    if self.current_chunk >= self.total_chunks then
        m.chunk_idx = 0
        m.num_rows = 0
        m.is_exhausted = true
    else
        m.chunk_idx = self.current_chunk
        m.num_rows = 0
        m.is_exhausted = false
        self.current_chunk = self.current_chunk + 1
    end
    C.pthread_mutex_unlock(&(self.mutex))
    return m
end

terra MorselQueue:reset()
    C.pthread_mutex_lock(&(self.mutex))
    self.current_chunk = 0
    C.pthread_mutex_unlock(&(self.mutex))
end

morsel.Morsel = Morsel
morsel.MorselQueue = MorselQueue
return morsel
