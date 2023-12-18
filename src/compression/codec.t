-- Quarry unified columnar compression analyzer and codec selector
-- Analyzes columnar entropy, cardinality, and runs to choose optimal encoding.

local C = require("src.common.c").C
local bitpack = require("src.compression/bitpack")
local delta_for = require("src.compression/delta_for")
local rle = require("src.compression/rle")
local dict = require("src.compression/dict")

local codec = {}

codec.RAW       = 0
codec.BITPACK   = 1
codec.DELTA_FOR = 2
codec.RLE       = 3
codec.DICT      = 4

-- Analyzes an integer sample array to determine the optimal compression codec
local terra analyze_integer_column_fn(sample: &int64, count: uint32) : int32
    if count <= 1 then return codec.RAW end

    -- Check for long runs (RLE candidate)
    var num_switches : uint32 = 0
    for i = 1, count do
        if sample[i] ~= sample[i - 1] then
            num_switches = num_switches + 1
        end
    end

    -- If run count is small (< 10% of total elements), RLE is optimal
    if num_switches < (count / 10) then
        return codec.RLE
    end

    -- Check range for Frame-of-Reference (FOR)
    var min_v = sample[0]
    var max_v = sample[0]
    for i = 1, count do
        if sample[i] < min_v then min_v = sample[i] end
        if sample[i] > max_v then max_v = sample[i] end
    end

    var max_delta = [uint64](max_v - min_v)
    var bits_needed = bitpack.required_bits_u64(max_delta)

    -- If bit width is significantly smaller than 64 bits (<= 16 bits), FOR is optimal
    if bits_needed <= 16 then
        return codec.DELTA_FOR
    end

    return codec.RAW
end

codec.analyze_integer_column = analyze_integer_column_fn
return codec
