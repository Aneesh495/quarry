-- Quarry validity mask subsystem
-- Arrow-compatible 64-bit word null bitmap: bit 1 indicates valid, bit 0 indicates null.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local bits = require("src.common.bits")

local mask = {}

struct ValidityMask {
    num_bits: uint32,
    num_words: uint32,
    words: &uint64,
    all_valid: bool
}

terra ValidityMask:init(capacity: uint32)
    self.num_bits = capacity
    self.num_words = (capacity + 63) >> 6
    self.words = [&uint64](alloc.aligned_alloc(self.num_words * sizeof(uint64), alloc.CACHE_LINE))
    self:set_all_valid()
end

terra ValidityMask:destroy()
    if self.words ~= nil then
        alloc.aligned_free(self.words)
        self.words = nil
    end
    self.num_bits = 0
    self.num_words = 0
    self.all_valid = true
end

terra ValidityMask:set_all_valid()
    C.memset(self.words, 0xFF, self.num_words * sizeof(uint64))
    self.all_valid = true
end

terra ValidityMask:set_all_null()
    C.memset(self.words, 0x00, self.num_words * sizeof(uint64))
    self.all_valid = false
end

terra ValidityMask:is_valid(idx: uint32) : bool
    if self.all_valid then return true end
    if idx >= self.num_bits then return false end
    var word_idx = idx >> 6
    var bit_idx = idx and 63
    return ((self.words[word_idx] >> bit_idx) and 1ULL) ~= 0ULL
end

terra ValidityMask:is_null(idx: uint32) : bool
    return not self:is_valid(idx)
end

terra ValidityMask:set_valid(idx: uint32)
    if idx >= self.num_bits then return end
    var word_idx = idx >> 6
    var bit_idx = idx and 63
    self.words[word_idx] = self.words[word_idx] or (1ULL << bit_idx)
end

terra ValidityMask:set_null(idx: uint32)
    if idx >= self.num_bits then return end
    self.all_valid = false
    var word_idx = idx >> 6
    var bit_idx = idx and 63
    self.words[word_idx] = self.words[word_idx] and (not (1ULL << bit_idx))
end

terra ValidityMask:count_valid() : uint32
    if self.all_valid then return self.num_bits end
    var count : uint32 = 0
    for i = 0, self.num_words do
        count = count + bits.popcount64(self.words[i])
    end
    if count > self.num_bits then count = self.num_bits end
    return count
end

terra ValidityMask:count_null() : uint32
    return self.num_bits - self:count_valid()
end

mask.ValidityMask = ValidityMask
return mask
