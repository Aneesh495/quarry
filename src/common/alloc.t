-- Quarry memory allocation subsystem
-- Provides cache line aligned allocation, thread local bump arenas, and tracking.

local C = require("src.common.c").C
local size_t = C.size_t

local alloc = {}

-- 64-byte alignment optimal for AVX-512, AVX2, and ARM NEON cache lines
alloc.CACHE_LINE = 64

-- Aligned memory allocation wrapper
local terra aligned_alloc_fn(nbytes: size_t, align_val: size_t) : &opaque
    var ptr : &opaque = nil
    var actual_align = align_val
    if actual_align < 8 then
        actual_align = 8
    end
    var res = C.posix_memalign(&ptr, actual_align, nbytes)
    if res ~= 0 then
        return nil
    end
    return ptr
end

local terra aligned_free_fn(ptr: &opaque)
    if ptr ~= nil then
        C.free(ptr)
    end
end

alloc.aligned_alloc = aligned_alloc_fn
alloc.aligned_free = aligned_free_fn

-- Arena block node
struct ArenaBlock {
    next: &ArenaBlock,
    capacity: size_t,
    offset: size_t,
    data: &uint8
}

-- Linear bump allocator for fast query-scoped allocations without lock contention
struct Arena {
    current: &ArenaBlock,
    head: &ArenaBlock,
    default_block_size: size_t,
    total_allocated: size_t
}

terra Arena:init(default_block_size: size_t)
    self.current = nil
    self.head = nil
    if default_block_size == 0 then
        self.default_block_size = 65536 -- 64 KB default block size
    else
        self.default_block_size = default_block_size
    end
    self.total_allocated = 0
end

terra Arena:new_block(min_size: size_t) : &ArenaBlock
    var block_size = self.default_block_size
    if min_size > block_size then
        block_size = min_size
    end

    var block_ptr = [&ArenaBlock](C.malloc(sizeof(ArenaBlock)))
    var raw_data = [&uint8](aligned_alloc_fn(block_size, alloc.CACHE_LINE))

    block_ptr.next = nil
    block_ptr.capacity = block_size
    block_ptr.offset = 0
    block_ptr.data = raw_data

    self.total_allocated = self.total_allocated + block_size + sizeof(ArenaBlock)
    return block_ptr
end

terra Arena:allocate(nbytes: size_t, align_val: size_t) : &opaque
    var actual_align = align_val
    if actual_align == 0 then
        actual_align = 8
    end

    if self.current == nil then
        var b = self:new_block(nbytes + actual_align)
        self.head = b
        self.current = b
    end

    var curr = self.current
    var offset = curr.offset
    var rem = offset % actual_align
    if rem ~= 0 then
        offset = offset + (actual_align - rem)
    end

    if offset + nbytes <= curr.capacity then
        var ptr = &(curr.data[offset])
        curr.offset = offset + nbytes
        return [&opaque](ptr)
    end

    var next_block = self:new_block(nbytes + actual_align)
    curr.next = next_block
    self.current = next_block

    var new_ptr = &(next_block.data[0])
    next_block.offset = nbytes
    return [&opaque](new_ptr)
end

terra Arena:reset()
    var node = self.head
    while node ~= nil do
        node.offset = 0
        node = node.next
    end
    self.current = self.head
end

terra Arena:destroy()
    var node = self.head
    while node ~= nil do
        var next_node = node.next
        if node.data ~= nil then
            aligned_free_fn(node.data)
        end
        C.free(node)
        node = next_node
    end
    self.head = nil
    self.current = nil
    self.total_allocated = 0
end

alloc.Arena = Arena
return alloc
