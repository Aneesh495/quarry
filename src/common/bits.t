-- Quarry bit manipulation utilities
-- Optimized population counts, leading/trailing zero scans, and bitfield packing.

local bits = {}

-- Population count for 64-bit unsigned integer (Hamming weight)
terra bits.popcount64(x: uint64) : uint32
    var v = x
    v = v - ((v >> 1) and 0x5555555555555555ULL)
    v = (v and 0x3333333333333333ULL) + ((v >> 2) and 0x3333333333333333ULL)
    v = (v + (v >> 4)) and 0x0F0F0F0F0F0F0F0FULL
    return [uint32]((v * 0x0101010101010101ULL) >> 56)
end

-- Population count for 32-bit unsigned integer
terra bits.popcount32(x: uint32) : uint32
    var v = x
    v = v - ((v >> 1) and 0x55555555U)
    v = (v and 0x33333333U) + ((v >> 2) and 0x33333333U)
    v = (v + (v >> 4)) and 0x0F0F0F0FU
    return (v * 0x01010101U) >> 24
end

-- Count trailing zeros in 64-bit word
terra bits.ctz64(x: uint64) : uint32
    if x == 0 then
        return 64
    end
    -- Use De Bruijn sequence multiplication
    var debruijn : uint64 = 0x03f79d71b4cb0a89ULL
    var index_table : uint8[64]
    index_table[0]  = 0;  index_table[1]  = 1;  index_table[2]  = 48; index_table[3]  = 2;
    index_table[4]  = 57; index_table[5]  = 49; index_table[6]  = 28; index_table[7]  = 3;
    index_table[8]  = 61; index_table[9]  = 58; index_table[10] = 50; index_table[11] = 42;
    index_table[12] = 38; index_table[13] = 29; index_table[14] = 17; index_table[15] = 4;
    index_table[16] = 62; index_table[17] = 55; index_table[18] = 59; index_table[19] = 36;
    index_table[20] = 53; index_table[21] = 51; index_table[22] = 43; index_table[23] = 22;
    index_table[24] = 45; index_table[25] = 39; index_table[26] = 33; index_table[27] = 30;
    index_table[28] = 24; index_table[29] = 18; index_table[30] = 12; index_table[31] = 5;
    index_table[32] = 63; index_table[33] = 47; index_table[34] = 56; index_table[35] = 27;
    index_table[36] = 60; index_table[37] = 41; index_table[38] = 37; index_table[39] = 16;
    index_table[40] = 54; index_table[41] = 35; index_table[42] = 52; index_table[43] = 21;
    index_table[44] = 44; index_table[45] = 32; index_table[46] = 23; index_table[47] = 11;
    index_table[48] = 46; index_table[49] = 26; index_table[50] = 40; index_table[51] = 15;
    index_table[52] = 34; index_table[53] = 20; index_table[54] = 31; index_table[55] = 10;
    index_table[56] = 25; index_table[57] = 14; index_table[58] = 19; index_table[59] = 9;
    index_table[60] = 13; index_table[61] = 8;  index_table[62] = 7;  index_table[63] = 6;

    var isolated_lsb = (x and ([uint64](-[int64](x))))
    var hash = (isolated_lsb * debruijn) >> 58
    return index_table[hash]
end

-- Test if bit at index is set in a 64-bit bitmap array
terra bits.is_bit_set(bitmap: &uint64, idx: uint64) : bool
    var word_idx = idx >> 6
    var bit_idx = idx and 63ULL
    return ((bitmap[word_idx] >> bit_idx) and 1ULL) ~= 0ULL
end

-- Set bit at index in a 64-bit bitmap array
terra bits.set_bit(bitmap: &uint64, idx: uint64) : void
    var word_idx = idx >> 6
    var bit_idx = idx and 63ULL
    bitmap[word_idx] = bitmap[word_idx] or (1ULL << bit_idx)
end

-- Clear bit at index in a 64-bit bitmap array
terra bits.clear_bit(bitmap: &uint64, idx: uint64) : void
    var word_idx = idx >> 6
    var bit_idx = idx and 63ULL
    bitmap[word_idx] = bitmap[word_idx] and (not (1ULL << bit_idx))
end

-- Bitmask generation for N bits (up to 64)
terra bits.mask64(num_bits: uint32) : uint64
    if num_bits >= 64 then
        return 0xFFFFFFFFFFFFFFFFULL
    elseif num_bits == 0 then
        return 0ULL
    else
        return (1ULL << num_bits) - 1ULL
    end
end

-- Round up to next power of two
terra bits.next_pow2(x: uint64) : uint64
    if x <= 1 then return 1 end
    var v = x - 1
    v = v or (v >> 1)
    v = v or (v >> 2)
    v = v or (v >> 4)
    v = v or (v >> 8)
    v = v or (v >> 16)
    v = v or (v >> 32)
    return v + 1
end

return bits
