-- Quarry high performance hashing subsystem
-- Provides MurmurHash3, FNV-1a, and 64-bit integer mix functions for hash joins and group-by.

local C = require("src.common.c").C
local size_t = C.size_t

local hash = {}

local terra hash_u64_fn(k: uint64) : uint64
    var x = k
    x = x ^ (x >> 33)
    x = x * 0xff51afd7ed558ccdULL
    x = x ^ (x >> 33)
    x = x * 0xc4ceb9fe1a85ec53ULL
    x = x ^ (x >> 33)
    return x
end

local terra hash_u32_fn(k: uint32) : uint32
    var x = k
    x = x ^ (x >> 16)
    x = x * 0x85ebca6bU
    x = x ^ (x >> 13)
    x = x * 0xc2b2ae35U
    x = x ^ (x >> 16)
    return x
end

local terra hash_bytes_fn(data: &uint8, len: size_t) : uint64
    var h : uint64 = 0xcbf29ce484222325ULL
    var prime : uint64 = 0x100000001b3ULL
    for i = 0, len do
        h = h ^ [uint64](data[i])
        h = h * prime
    end
    return h
end

local terra hash_string_fn(str: &int8) : uint64
    if str == nil then return 0ULL end
    var len = C.strlen(str)
    return hash_bytes_fn([&uint8](str), len)
end

local terra combine_u64_fn(h1: uint64, h2: uint64) : uint64
    return h1 ^ (h2 + 0x9e3779b97f4a7c15ULL + (h1 << 6) + (h1 >> 2))
end

hash.hash_u64 = hash_u64_fn
hash.hash_u32 = hash_u32_fn
hash.hash_bytes = hash_bytes_fn
hash.hash_string = hash_string_fn
hash.combine_u64 = combine_u64_fn

return hash
