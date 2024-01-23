-- Quarry compiled kernel cache subsystem
-- Caches JIT compiled native function pointers to amortize LLVM compilation times.

local C = require("src.common.c").C
local hash = require("src.common.hash")

local cache = {}

cache.CACHE_CAPACITY = 64

struct CacheEntry {
    plan_hash: uint64,
    fn_ptr: &opaque,
    is_valid: bool
}

struct KernelCache {
    entries: CacheEntry[64],
    hits: uint64,
    misses: uint64
}

terra KernelCache:init()
    C.memset(&(self.entries), 0, sizeof(CacheEntry) * cache.CACHE_CAPACITY)
    self.hits = 0
    self.misses = 0
end

terra KernelCache:lookup(h: uint64) : &opaque
    var slot = [uint32](h % cache.CACHE_CAPACITY)
    if self.entries[slot].is_valid and self.entries[slot].plan_hash == h then
        self.hits = self.hits + 1
        return self.entries[slot].fn_ptr
    end
    self.misses = self.misses + 1
    return nil
end

terra KernelCache:insert(h: uint64, ptr: &opaque)
    var slot = [uint32](h % cache.CACHE_CAPACITY)
    self.entries[slot].plan_hash = h
    self.entries[slot].fn_ptr = ptr
    self.entries[slot].is_valid = true
end

cache.KernelCache = KernelCache
return cache
