-- Quarry high performance hashing subsystem
-- Provides MurmurHash3, FNV-1a, and 64-bit integer mix functions for hash joins and group-by.

local C = require("src.common.c").C

local hash = {}

-- MurmurHash3 64-bit integer finalizer (fmix64)
-- Excellent avalanche properties with zero collisions on consecutive dense keys
terra hash.hash_u64(k: uint64) : uint64
    var x = k
    x = x ^ (x >> 33)
    x = x * 0xff51afd7ed558ccdULL
    x = x ^ (x >> 33)
    x = x * 0xc4ceb9fe1a85ec53ULL
    x = x ^ (x >> 33)
    return x
end

-- 32-bit integer finalizer (fmix32)
terra hash.hash_u32(k: uint32) : uint32
    var x = k
    x = x ^ (x >> 16)
    x = x * 0x85ebca6bU
    x = x ^ (x >> 13)
    x = x * 0xc2b2ae35U
    x = x ^ (x >> 16)
    return x
end

-- Fast FNV-1a 64-bit hash for byte buffers and strings
terra hash.hash_bytes(data: &uint8, len: C.size_t) : uint64
    var h : uint64 = 0xcbf29ce484222325ULL
    var prime : uint64 = 0x100000001b3ULL
    for i = 0, len do
        h = h ^ [uint64](data[i])
        h = h * prime
    end
    return h
end

-- Fast FNV-1a for null-terminated strings
terra hash.hash_string(str: &int8) : uint64
    if str == nil then return 0ULL end
    var len = C.strlen(str)
    return hash.hash_bytes([&uint8](str), len)
end

-- Combine two 64-bit hashes using Boost/SplitMix golden ratio shift
terra hash.combine_u64(h1: uint64, h2: uint64) : uint64
    return h1 ^ (h2 + 0x9e3779b97f4a7c15ULL + (h1 << 6) + (h1 >> 2))
end

return hash
