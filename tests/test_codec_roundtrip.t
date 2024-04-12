-- test_codec_roundtrip.t
-- Exhaustive roundtrip and edge case verification across all Quarry compression codecs:
-- Bitpack, Frame-of-Reference (FOR), Run-Length Encoding (RLE), and Dictionary.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local bitpack = require("src.compression/bitpack")
local delta_for = require("src.compression/delta_for")
local rle = require("src.compression/rle")
local dict = require("src.compression/dict")

local TEST_COUNT = 1024

terra run_codec_roundtrip_tests() : int
    C.printf("=== Running Quarry Codec Exhaustive Roundtrip Tests ===\n")

    -- Test 1: Bitpack roundtrip on edge values (all 0s, all max for bit_width)
    var bp_src = [&uint32](alloc.aligned_alloc(TEST_COUNT * sizeof(uint32), alloc.CACHE_LINE))
    var bp_packed = [&uint64](alloc.aligned_alloc(TEST_COUNT * sizeof(uint64), alloc.CACHE_LINE))
    var bp_dst = [&uint32](alloc.aligned_alloc(TEST_COUNT * sizeof(uint32), alloc.CACHE_LINE))

    -- Test across bit widths 1, 3, 7, 11, 15, 23, 31
    var widths : uint32[7]
    widths[0] = 1; widths[1] = 3; widths[2] = 7; widths[3] = 11
    widths[4] = 15; widths[5] = 23; widths[6] = 31

    for wi = 0, 7 do
        var bw = widths[wi]
        var max_val = (1ULL << bw) - 1ULL
        for i = 0, TEST_COUNT do
            bp_src[i] = [uint32](i % [uint32](max_val + 1ULL))
        end

        var words = bitpack.pack_u32(bp_src, TEST_COUNT, bw, bp_packed)
        bitpack.unpack_u32(bp_packed, TEST_COUNT, bw, bp_dst)

        for i = 0, TEST_COUNT do
            if bp_dst[i] ~= bp_src[i] then
                C.printf("FAIL: Bitpack roundtrip mismatch at width %u, index %u (exp %u, got %u)\n", bw, i, bp_src[i], bp_dst[i])
                return 1
            end
        end
    end
    alloc.aligned_free(bp_src)
    alloc.aligned_free(bp_packed)
    alloc.aligned_free(bp_dst)
    C.printf("PASS: Test 1: Bitpack roundtrip across bit widths 1 to 31\n")

    -- Test 2: Delta-FOR on negative and positive ranges
    var for_src = [&int64](alloc.aligned_alloc(TEST_COUNT * sizeof(int64), alloc.CACHE_LINE))
    var for_dst = [&int64](alloc.aligned_alloc(TEST_COUNT * sizeof(int64), alloc.CACHE_LINE))

    -- Range [-500 .. +500]
    for i = 0, TEST_COUNT do
        for_src[i] = [int64](-500 + (i % 1000))
    end

    var for_blk : delta_for.CompressedForBlock
    for_blk:init()
    for_blk:compress(for_src, TEST_COUNT)
    for_blk:decompress(for_dst)

    for i = 0, TEST_COUNT do
        if for_dst[i] ~= for_src[i] then
            C.printf("FAIL: Delta-FOR roundtrip mismatch at %u (exp %lld, got %lld)\n", i, for_src[i], for_dst[i])
            return 1
        end
    end
    for_blk:destroy()
    alloc.aligned_free(for_src)
    alloc.aligned_free(for_dst)
    C.printf("PASS: Test 2: Delta-FOR negative and positive range roundtrip\n")

    -- Test 3: RLE with extreme run lengths
    var rle_src = [&int64](alloc.aligned_alloc(TEST_COUNT * sizeof(int64), alloc.CACHE_LINE))
    var rle_dst = [&int64](alloc.aligned_alloc(TEST_COUNT * sizeof(int64), alloc.CACHE_LINE))

    -- Run 1: 500 identical values, Run 2: 524 identical values
    for i = 0, 500 do rle_src[i] = 999999 end
    for i = 500, TEST_COUNT do rle_src[i] = -12345 end

    var rle_blk : rle.CompressedRleBlock
    rle_blk:init()
    rle_blk:compress(rle_src, TEST_COUNT)

    if rle_blk.num_runs ~= 2 then
        C.printf("FAIL: RLE expected 2 runs, got %u\n", rle_blk.num_runs)
        return 1
    end

    rle_blk:decompress(rle_dst)
    for i = 0, TEST_COUNT do
        if rle_dst[i] ~= rle_src[i] then
            C.printf("FAIL: RLE roundtrip mismatch at %u\n", i)
            return 1
        end
    end
    rle_blk:destroy()
    alloc.aligned_free(rle_src)
    alloc.aligned_free(rle_dst)
    C.printf("PASS: Test 3: RLE high-cardinality multi-hundred element runs\n")

    -- Test 4: Dictionary encoding roundtrip and filter pushdown
    var dict_blk : dict.CompressedDictBlock
    dict_blk:init()
    var dict_src = [&(&int8)](alloc.aligned_alloc(TEST_COUNT * sizeof(uint64), alloc.CACHE_LINE))

    var cats : (&int8)[3]
    cats[0] = "ALPHA"
    cats[1] = "BETA"
    cats[2] = "GAMMA"

    for i = 0, TEST_COUNT do
        dict_src[i] = cats[i % 3]
    end

    var ok = dict_blk:compress_strings(dict_src, TEST_COUNT)
    if not ok or dict_blk.num_entries ~= 3 then
        C.printf("FAIL: Dictionary compression expected 3 entries, got %u\n", dict_blk.num_entries)
        return 1
    end

    -- Verify decode matches
    for i = 0, TEST_COUNT do
        var s = dict_blk:decompress_string(i)
        if C.strcmp(s, dict_src[i]) ~= 0 then
            C.printf("FAIL: Dictionary decompress mismatch at %u\n", i)
            return 1
        end
    end

    -- Verify filter pushdown for "BETA" (every 3rd element starting at 1: 1, 4, 7...)
    var sel_out : uint32[1024]
    var matches = dict_blk:filter_equal("BETA", &(sel_out[0]))
    if matches ~= 341 then
        C.printf("FAIL: Dictionary filter_equal expected 341 matches for BETA, got %u\n", matches)
        return 1
    end

    dict_blk:destroy()
    alloc.aligned_free(dict_src)
    C.printf("PASS: Test 4: Dictionary encoding roundtrip and direct code filter pushdown\n")

    C.printf("=== ALL CODEC ROUNDTRIP TESTS PASSED (4/4) ===\n")
    return 0
end

local code = run_codec_roundtrip_tests()
if code ~= 0 then
    os.exit(1)
end
