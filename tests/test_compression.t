-- Test suite for Quarry columnar compression subsystem

local C = require("src.common.c").C
local bitpack = require("src.compression/bitpack")
local delta_for = require("src.compression/delta_for")
local rle = require("src.compression/rle")
local dict = require("src.compression/dict")
local codec = require("src.compression/codec")

terra run_compression_tests() : int
    C.printf("=== Running Quarry Columnar Compression Tests ===\n")

    -- Test 1: Bitpack roundtrip for various bit-widths
    var src : uint32[100]
    var unpacked : uint32[100]
    var packed : uint64[100]

    -- Test 7-bit values (range 0..127)
    for i = 0, 100 do
        src[i] = i and 127
    end
    bitpack.pack_u32(&(src[0]), 100, 7, &(packed[0]))
    bitpack.unpack_u32(&(packed[0]), 100, 7, &(unpacked[0]))

    for i = 0, 100 do
        if src[i] ~= unpacked[i] then
            C.printf("FAIL: bitpack 7-bit roundtrip failed at %u (expected %u, got %u)\n", i, src[i], unpacked[i])
            return 1
        end
    end

    -- Test 13-bit values (range 0..8191)
    for i = 0, 100 do
        src[i] = (i * 73) and 8191
    end
    bitpack.pack_u32(&(src[0]), 100, 13, &(packed[0]))
    bitpack.unpack_u32(&(packed[0]), 100, 13, &(unpacked[0]))

    for i = 0, 100 do
        if src[i] ~= unpacked[i] then
            C.printf("FAIL: bitpack 13-bit roundtrip failed at %u\n", i)
            return 1
        end
    end
    C.printf("PASS: Bit-packing and unpacking across arbitrary bit-widths\n")

    -- Test 2: Frame-of-Reference (FOR) compression
    var for_src : int64[1000]
    var for_dst : int64[1000]
    -- Clustered integers around 1,000,000 with small deltas
    for i = 0, 1000 do
        for_src[i] = 1000000 + (i % 200)
    end

    var for_block : delta_for.CompressedForBlock
    for_block:init()
    for_block:compress(&(for_src[0]), 1000)

    if for_block.base_value ~= 1000000 or for_block.bit_width > 8 then
        C.printf("FAIL: FOR base or bit width incorrect (base=%lld, width=%u)\n", for_block.base_value, for_block.bit_width)
        return 1
    end

    for_block:decompress(&(for_dst[0]))
    for i = 0, 1000 do
        if for_src[i] ~= for_dst[i] then
            C.printf("FAIL: FOR decompression mismatch at %u\n", i)
            return 1
        end
    end
    for_block:destroy()
    C.printf("PASS: Frame-of-Reference compression and decompression roundtrip\n")

    -- Test 3: Run-Length Encoding (RLE) and Direct Predicate Evaluation
    var rle_src : int64[100]
    var rle_dst : int64[100]
    -- 50 copies of 10, then 50 copies of 20
    for i = 0, 50 do rle_src[i] = 10 end
    for i = 50, 100 do rle_src[i] = 20 end

    var rle_blk : rle.CompressedRleBlock
    rle_blk:init()
    rle_blk:compress(&(rle_src[0]), 100)

    if rle_blk.num_runs ~= 2 then
        C.printf("FAIL: RLE expected 2 runs, got %u\n", rle_blk.num_runs)
        return 1
    end

    rle_blk:decompress(&(rle_dst[0]))
    for i = 0, 100 do
        if rle_src[i] ~= rle_dst[i] then
            C.printf("FAIL: RLE decompression mismatch at %u\n", i)
            return 1
        end
    end

    -- Direct predicate evaluation on RLE without decompressing
    var rle_sel : uint32[100]
    var matched_20 = rle_blk:filter_equal(20, &(rle_sel[0]))
    if matched_20 ~= 50 then
        C.printf("FAIL: RLE filter_equal expected 50 matches, got %u\n", matched_20)
        return 1
    end
    if rle_sel[0] ~= 50 or rle_sel[49] ~= 99 then
        C.printf("FAIL: RLE matched row indices incorrect\n")
        return 1
    end
    rle_blk:destroy()
    C.printf("PASS: Run-Length Encoding and direct predicate pushdown\n")

    -- Test 4: Dictionary Encoding
    var dict_blk : dict.CompressedDictBlock
    dict_blk:init()

    var test_strings : (&int8)[6]
    test_strings[0] = "NYC"
    test_strings[1] = "SFO"
    test_strings[2] = "LON"
    test_strings[3] = "NYC"
    test_strings[4] = "SFO"
    test_strings[5] = "NYC"

    var ok = dict_blk:compress_strings(&(test_strings[0]), 6)
    if not ok or dict_blk.num_entries ~= 3 then
        C.printf("FAIL: dict compression failed or entry count wrong\n")
        return 1
    end

    for i = 0, 6 do
        var dec = dict_blk:decompress_string(i)
        if C.strcmp(dec, test_strings[i]) ~= 0 then
            C.printf("FAIL: dict decompression mismatch at %u\n", i)
            return 1
        end
    end

    -- Direct filter pushdown for "NYC"
    var dict_sel : uint32[6]
    var matched_nyc = dict_blk:filter_equal("NYC", &(dict_sel[0]))
    if matched_nyc ~= 3 then
        C.printf("FAIL: dict filter_equal expected 3 matches, got %u\n", matched_nyc)
        return 1
    end
    if dict_sel[0] ~= 0 or dict_sel[1] ~= 3 or dict_sel[2] ~= 5 then
        C.printf("FAIL: dict matched indices incorrect\n")
        return 1
    end
    dict_blk:destroy()
    C.printf("PASS: Dictionary encoding and direct code filter pushdown\n")

    -- Test 5: Codec auto-selection
    var rle_sample : int64[100]
    for i = 0, 100 do rle_sample[i] = i / 25 end -- only 4 switches
    var chosen_rle = codec.analyze_integer_column(&(rle_sample[0]), 100)
    if chosen_rle ~= codec.RLE then
        C.printf("FAIL: expected codec.RLE, got %d\n", chosen_rle)
        return 1
    end

    var for_sample : int64[100]
    for i = 0, 100 do for_sample[i] = 5000000 + i end
    var chosen_for = codec.analyze_integer_column(&(for_sample[0]), 100)
    if chosen_for ~= codec.DELTA_FOR then
        C.printf("FAIL: expected codec.DELTA_FOR, got %d\n", chosen_for)
        return 1
    end
    C.printf("PASS: Entropy-based automatic compression codec selection\n")

    C.printf("=== ALL COMPRESSION TESTS PASSED (5/5) ===\n")
    return 0
end

local code = run_compression_tests()
if code ~= 0 then
    os.exit(1)
end
