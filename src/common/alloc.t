-- Quarry memory allocation subsystem
-- Provides cache line aligned allocation, thread local bump arenas, and tracking.

local C = require("src.common.c").C

local alloc = {}

-- 64-byte alignment optimal for AVX-512, AVX2, and ARM NEON cache lines
alloc.CACHE_LINE = 64

-- Aligned memory allocation wrapper
terra alloc.aligned_alloc(size: C.size_t, alignment: C.size_t) : &opaque
    var ptr : &opaque = nil
    var align_val = alignment
    if align_val < sizeof(&opaque) then
        align_val = sizeof(&opaque)
    end
    var res = C.posix_memalign(&ptr, align_val, size)
    if res ~= 0 then
        return nil
    end
    return ptr
end

terra alloc.aligned_free(ptr: &opaque) : void
    if ptr ~= nil then
        C.free(ptr)
    end
end

-- Arena block node
struct ArenaBlock {
    next: &ArenaBlock,
    capacity: C.size_t,
    offset: C.size_t,
    data: &uint8
}

-- Linear bump allocator for fast query-scoped allocations without lock contention
struct Arena {
    current: &ArenaBlock,
    head: &ArenaBlock,
    default_block_size: C.size_t,
    total_allocated: C.size_t
}

terra Arena:init(default_block_size: C.size_t) : void
    self.current = nil
    self.head = nil
    if default_block_size == 0 then
        self.default_block_size = 65536 -- 64 KB default block size
    else
        self.default_block_size = default_block_size
    end
    self.total_allocated = 0
end

terra Arena:new_block(min_size: C.size_t) : &ArenaBlock
    var block_size = self.default_block_size
    if min_size > block_size then
        block_size = min_size
    end

    var block_ptr = [&ArenaBlock](C.malloc(sizeof(ArenaBlock)))
    var raw_data = [&uint8](alloc.aligned_alloc(block_size, alloc.CACHE_LINE))

    block_ptr.next = nil
    block_ptr.capacity = block_size
    block_ptr.offset = 0
    block_ptr.data = raw_data

    self.total_allocated = self.total_allocated + block_size + sizeof(ArenaBlock)
    return block_ptr
end

terra Arena:allocate(size: C.size_t, alignment: C.size_t) : &opaque
    var align_val = alignment
    if align_val == 0 then
        align_val = 8
    end

    if self.current == nil then
        var b = self:new_block(size + align_val)
        self.head = b
        self.current = b
    end

    -- Align offset up to alignment boundary
    var curr = self.current
    var offset = curr.offset
    var rem = offset % align_val
    if rem ~= 0 then
        offset = offset + (align_val - rem)
    end

    if offset + size <= curr.capacity then
        var ptr = &(curr.data[offset])
        curr.offset = offset + size
        return [&opaque](ptr)
    end

    -- Allocate a new block
    var next_block = self:new_block(size + align_val)
    curr.next = next_block
    self.current = next_block

    var new_ptr = &(next_block.data[0])
    next_block.offset = size
    return [&opaque](new_ptr)
end

terra Arena:reset() : void
    var node = self.head
    while node ~= nil do
        node.offset = 0
        node = node.next
    end
    self.current = self.head
end

terra Arena:destroy() : void
    var node = self.head
    while node ~= nil do
        var next_node = node.next
        if node.data ~= nil then
            alloc.aligned_free(node.data)
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
