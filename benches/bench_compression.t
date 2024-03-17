-- bench_compression.t
-- Micro-benchmark evaluating compression ratios and decode throughput
-- across Bit-packing, Delta-FOR, RLE, and Dictionary codecs.

local C = require("src.common.c").C
local timer = require("src.common.timer")
local alloc = require("src.common.alloc")
local bitpack = require("src.compression/bitpack")
local delta_for = require("src.compression/delta_for")
local rle = require("src.compression/rle")
local dict = require("src.compression/dict")

local N = 100000

local terra run_compression_bench() : int
    C.printf("=================================================================\n")
    C.printf("  QUARRY COLUMNAR COMPRESSION BENCHMARKS (%d Values)\n", N)
    C.printf("=================================================================\n")

    -- 1. Bitpack Benchmark: small integers fitting in 5 bits (0..31)
    var bp_src = [&uint32](alloc.aligned_alloc(N * sizeof(uint32), alloc.CACHE_LINE))
    var bp_dst = [&uint64](alloc.aligned_alloc(N * sizeof(uint64), alloc.CACHE_LINE))
    var bp_dec = [&uint32](alloc.aligned_alloc(N * sizeof(uint32), alloc.CACHE_LINE))
    for i = 0, N do bp_src[i] = [uint32](i % 30) end

    var sw_bp : timer.Stopwatch
    sw_bp:start()
    var bp_words = bitpack.pack_u32(bp_src, N, 5, bp_dst)
    sw_bp:stop()
    var bp_enc_us = sw_bp:elapsed_us()

    sw_bp:start()
    bitpack.unpack_u32(bp_dst, N, 5, bp_dec)
    sw_bp:stop()
    var bp_dec_us = sw_bp:elapsed_us()

    var bp_raw_bytes = N * sizeof(uint32)
    var bp_comp_bytes = bp_words * sizeof(uint64)
    var bp_ratio = [double](bp_raw_bytes) / [double](bp_comp_bytes)
    var bp_m_vals_sec = [double](N) / [double](bp_dec_us)

    C.printf("Codec       | Raw (KB) | Comp (KB) | Ratio | Enc (us) | Dec (us) | Dec (M/s)\n")
    C.printf("------------|----------|-----------|-------|----------|----------|----------\n")
    C.printf("Bitpack 5b  | %8.1f | %9.1f | %4.2fx | %8.1f | %8.1f | %8.2f\n",
        [double](bp_raw_bytes) / 1024.0, [double](bp_comp_bytes) / 1024.0, bp_ratio, bp_enc_us, bp_dec_us, bp_m_vals_sec)

    -- 2. Delta-FOR Benchmark: narrow range integers [1000000..1000050]
    var for_src = [&int64](alloc.aligned_alloc(N * sizeof(int64), alloc.CACHE_LINE))
    var for_dec = [&int64](alloc.aligned_alloc(N * sizeof(int64), alloc.CACHE_LINE))
    for i = 0, N do for_src[i] = [int64](1000000 + (i % 50)) end

    var for_blk : delta_for.CompressedForBlock
    for_blk:init()

    var sw_for : timer.Stopwatch
    sw_for:start()
    for_blk:compress(for_src, N)
    sw_for:stop()
    var for_enc_us = sw_for:elapsed_us()

    sw_for:start()
    for_blk:decompress(for_dec)
    sw_for:stop()
    var for_dec_us = sw_for:elapsed_us()

    var for_raw_bytes = N * sizeof(int64)
    var for_comp_bytes = for_blk.num_words * sizeof(uint64) + sizeof(int64) + 4
    var for_ratio = [double](for_raw_bytes) / [double](for_comp_bytes)
    var for_m_vals_sec = [double](N) / [double](for_dec_us)

    C.printf("Delta-FOR   | %8.1f | %9.1f | %4.2fx | %8.1f | %8.1f | %8.2f\n",
        [double](for_raw_bytes) / 1024.0, [double](for_comp_bytes) / 1024.0, for_ratio, for_enc_us, for_dec_us, for_m_vals_sec)

    -- 3. RLE Benchmark: long runs of repeating numbers (100 distinct runs of 1000)
    var rle_src = [&int64](alloc.aligned_alloc(N * sizeof(int64), alloc.CACHE_LINE))
    var rle_dec = [&int64](alloc.aligned_alloc(N * sizeof(int64), alloc.CACHE_LINE))
    for i = 0, N do rle_src[i] = [int64](i / 1000) end

    var rle_blk : rle.CompressedRleBlock
    rle_blk:init()

    var sw_rle : timer.Stopwatch
    sw_rle:start()
    rle_blk:compress(rle_src, N)
    sw_rle:stop()
    var rle_enc_us = sw_rle:elapsed_us()

    sw_rle:start()
    rle_blk:decompress(rle_dec)
    sw_rle:stop()
    var rle_dec_us = sw_rle:elapsed_us()

    var rle_raw_bytes = N * sizeof(int64)
    var rle_comp_bytes = rle_blk.num_runs * (sizeof(int64) + sizeof(uint32))
    var rle_ratio = [double](rle_raw_bytes) / [double](rle_comp_bytes)
    var rle_m_vals_sec = [double](N) / [double](rle_dec_us)

    C.printf("RLE (Runs)  | %8.1f | %9.1f | %4.2fx | %8.1f | %8.1f | %8.2f\n",
        [double](rle_raw_bytes) / 1024.0, [double](rle_comp_bytes) / 1024.0, rle_ratio, rle_enc_us, rle_dec_us, rle_m_vals_sec)

    -- 4. Dictionary Encoding Benchmark: low-cardinality string categories
    var dict_blk : dict.CompressedDictBlock
    dict_blk:init()
    var raw_strings = [&(&int8)](alloc.aligned_alloc(N * sizeof(uint64), alloc.CACHE_LINE))
    var s0 : &int8 = "AUTOMOBILE"
    var s1 : &int8 = "BUILDING"
    var s2 : &int8 = "FURNITURE"
    var s3 : &int8 = "MACHINERY"
    for i = 0, N do
        var m = i % 4
        if m == 0 then raw_strings[i] = s0
        elseif m == 1 then raw_strings[i] = s1
        elseif m == 2 then raw_strings[i] = s2
        else raw_strings[i] = s3 end
    end

    var sw_dict : timer.Stopwatch
    sw_dict:start()
    dict_blk:compress_strings(raw_strings, N)
    sw_dict:stop()
    var dict_enc_us = sw_dict:elapsed_us()

    sw_dict:start()
    var check_count : uint32 = 0
    for rep = 0, 10 do
        for i = 0, N do
            var s = dict_blk:decompress_string(i)
            if s[0] == 65 then check_count = check_count + 1 end
        end
    end
    sw_dict:stop()
    var dict_dec_us = sw_dict:elapsed_us() / 10.0

    if dict_dec_us < 1.0 then dict_dec_us = 1.0 end
    var dict_raw_bytes = N * 10
    var dict_comp_bytes = N * sizeof(uint8) + dict_blk.num_entries * 64
    var dict_ratio = [double](dict_raw_bytes) / [double](dict_comp_bytes)
    var dict_m_vals_sec = [double](N) / [double](dict_dec_us)

    C.printf("Dictionary  | %8.1f | %9.1f | %4.2fx | %8.1f | %8.1f | %8.2f\n",
        [double](dict_raw_bytes) / 1024.0, [double](dict_comp_bytes) / 1024.0, dict_ratio, dict_enc_us, dict_dec_us, dict_m_vals_sec)

    C.printf("=================================================================\n")

    alloc.aligned_free(bp_src)
    alloc.aligned_free(bp_dst)
    alloc.aligned_free(bp_dec)
    alloc.aligned_free(for_src)
    alloc.aligned_free(for_dec)
    alloc.aligned_free(rle_src)
    alloc.aligned_free(rle_dec)
    alloc.aligned_free(raw_strings)
    for_blk:destroy()
    rle_blk:destroy()
    dict_blk:destroy()
    return 0
end

local code = run_compression_bench()
if code ~= 0 then os.exit(1) end
