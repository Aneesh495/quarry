-- Quarry Frame-of-Reference (FOR) and Delta-FOR encoding subsystem
-- Compresses sorted or clustered integer sequences by storing minimum base plus bit-packed deltas.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local bitpack = require("src.compression/bitpack")

local delta_for = {}

struct CompressedForBlock {
    base_value: int64,
    bit_width: uint32,
    count: uint32,
    num_words: uint32,
    data: &uint64
}

terra CompressedForBlock:init()
    self.base_value = 0
    self.bit_width = 0
    self.count = 0
    self.num_words = 0
    self.data = nil
end

terra CompressedForBlock:destroy()
    if self.data ~= nil then
        alloc.aligned_free(self.data)
        self.data = nil
    end
    self.count = 0
    self.num_words = 0
end

-- Compresses an array of int64 values into a CompressedForBlock
terra CompressedForBlock:compress(src: &int64, count: uint32)
    if count == 0 then return end
    self.count = count

    var min_val = src[0]
    var max_val = src[0]
    for i = 1, count do
        if src[i] < min_val then min_val = src[i] end
        if src[i] > max_val then max_val = src[i] end
    end

    self.base_value = min_val
    var max_delta = [uint64](max_val - min_val)
    self.bit_width = bitpack.required_bits_u64(max_delta)

    -- Temporary delta buffer
    var deltas = [&uint32](C.malloc(count * sizeof(uint32)))
    for i = 0, count do
        deltas[i] = [uint32](src[i] - min_val)
    end

    var total_bits = [uint64](count) * [uint64](self.bit_width)
    self.num_words = [uint32]((total_bits + 63) >> 6)
    self.data = [&uint64](alloc.aligned_alloc(self.num_words * sizeof(uint64), alloc.CACHE_LINE))

    bitpack.pack_u32(deltas, count, self.bit_width, self.data)
    C.free(deltas)
end

-- Decompresses block back into destination int64 array
terra CompressedForBlock:decompress(dst: &int64)
    if self.count == 0 or self.data == nil then return end

    var deltas = [&uint32](C.malloc(self.count * sizeof(uint32)))
    bitpack.unpack_u32(self.data, self.count, self.bit_width, deltas)

    var base = self.base_value
    for i = 0, self.count do
        dst[i] = base + [int64](deltas[i])
    end

    C.free(deltas)
end

delta_for.CompressedForBlock = CompressedForBlock
return delta_for
