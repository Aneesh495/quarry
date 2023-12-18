-- Quarry bit-packing compression subsystem
-- Packs integers into arbitrary bit-widths (1 to 32 bits) for high compression ratios.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local bits = require("src.common.bits")

local bitpack = {}

-- Computes the minimum number of bits required to store value max_val
local terra required_bits_u64_fn(max_val: uint64) : uint32
    if max_val == 0 then return 1 end
    var b : uint32 = 0
    var v = max_val
    while v > 0 do
        b = b + 1
        v = v >> 1
    end
    return b
end

-- Packs array of uint32 values into a 64-bit word buffer using bit_width bits per value
local terra pack_u32_fn(src: &uint32, count: uint32, bit_width: uint32, dst: &uint64) : uint32
    if bit_width == 0 or count == 0 then return 0 end
    var total_bits = [uint64](count) * [uint64](bit_width)
    var num_words = [uint32]((total_bits + 63) >> 6)
    C.memset(dst, 0, num_words * sizeof(uint64))

    var mask = bits.mask64(bit_width)

    for i = 0, count do
        var val = [uint64](src[i]) and mask
        var bit_offset = [uint64](i) * [uint64](bit_width)
        var word_idx = bit_offset >> 6
        var bit_pos = bit_offset and 63ULL

        dst[word_idx] = dst[word_idx] or (val << bit_pos)

        -- If bits spill over into the next 64-bit word
        if bit_pos + [uint64](bit_width) > 64ULL then
            var spilled_bits = (bit_pos + [uint64](bit_width)) - 64ULL
            var shift_remaining = [uint64](bit_width) - spilled_bits
            dst[word_idx + 1] = dst[word_idx + 1] or (val >> shift_remaining)
        end
    end

    return num_words
end

-- Unpacks 64-bit word buffer into uint32 values
local terra unpack_u32_fn(src: &uint64, count: uint32, bit_width: uint32, dst: &uint32)
    if bit_width == 0 or count == 0 then return end
    var mask = bits.mask64(bit_width)

    for i = 0, count do
        var bit_offset = [uint64](i) * [uint64](bit_width)
        var word_idx = bit_offset >> 6
        var bit_pos = bit_offset and 63ULL

        var val = (src[word_idx] >> bit_pos) and mask

        if bit_pos + [uint64](bit_width) > 64ULL then
            var spilled_bits = (bit_pos + [uint64](bit_width)) - 64ULL
            var shift_remaining = [uint64](bit_width) - spilled_bits
            var high_part = (src[word_idx + 1] and bits.mask64([uint32](spilled_bits))) << shift_remaining
            val = val or high_part
        end

        dst[i] = [uint32](val)
    end
end

bitpack.required_bits_u64 = required_bits_u64_fn
bitpack.pack_u32 = pack_u32_fn
bitpack.unpack_u32 = unpack_u32_fn

return bitpack
