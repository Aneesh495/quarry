-- Test suite for Quarry common infrastructure

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local bits = require("src.common.bits")
local hash = require("src.common.hash")
local status = require("src.common.status")
local timer = require("src.common.timer")
local simd = require("src.common.simd")

terra run_common_tests() : int
    C.printf("=== Running Quarry Common Infrastructure Tests ===\n")

    -- Test 1: Aligned Allocation
    var raw = alloc.aligned_alloc(1024, 64)
    if raw == nil then
        C.printf("FAIL: aligned_alloc returned nil\n")
        return 1
    end
    var addr = [uint64](raw)
    if (addr % 64ULL) ~= 0ULL then
        C.printf("FAIL: pointer is not 64-byte aligned: %llu\n", addr)
        return 1
    end
    alloc.aligned_free(raw)
    C.printf("PASS: Aligned memory allocation (64-byte boundary)\n")

    -- Test 2: Arena Allocation
    var arena : alloc.Arena
    arena:init(4096)
    var p1 = arena:allocate(128, 16)
    var p2 = arena:allocate(256, 16)
    if p1 == nil or p2 == nil then
        C.printf("FAIL: arena allocation failed\n")
        return 1
    end
    arena:reset()
    var p3 = arena:allocate(64, 8)
    if p3 == nil then
        C.printf("FAIL: arena allocate after reset failed\n")
        return 1
    end
    arena:destroy()
    C.printf("PASS: Bump arena allocation, reset, and teardown\n")

    -- Test 3: Bit manipulation
    var pop64 = bits.popcount64(0xAAAAAAAAAAAAAAAAULL)
    if pop64 ~= 32 then
        C.printf("FAIL: popcount64 expected 32, got %u\n", pop64)
        return 1
    end
    var ctz = bits.ctz64(0x0000000000000008ULL)
    if ctz ~= 3 then
        C.printf("FAIL: ctz64 expected 3, got %u\n", ctz)
        return 1
    end
    var bmap : uint64[2]
    bmap[0] = 0; bmap[1] = 0
    bits.set_bit(&(bmap[0]), 5)
    bits.set_bit(&(bmap[0]), 70)
    if not bits.is_bit_set(&(bmap[0]), 5) or not bits.is_bit_set(&(bmap[0]), 70) then
        C.printf("FAIL: is_bit_set failed\n")
        return 1
    end
    bits.clear_bit(&(bmap[0]), 5)
    if bits.is_bit_set(&(bmap[0]), 5) then
        C.printf("FAIL: clear_bit failed\n")
        return 1
    end
    C.printf("PASS: Bitwise popcount, ctz, and bitmap indexing\n")

    -- Test 4: Hashing
    var h1 = hash.hash_u64(100ULL)
    var h2 = hash.hash_u64(101ULL)
    if h1 == h2 or h1 == 0ULL then
        C.printf("FAIL: hash_u64 collision or zero\n")
        return 1
    end
    var str_hash = hash.hash_string("quarry_olap_engine")
    if str_hash == 0ULL then
        C.printf("FAIL: hash_string produced zero\n")
        return 1
    end
    C.printf("PASS: MurmurHash3 fmix64 and FNV-1a hashing\n")

    -- Test 5: Status
    var s_ok = status.ok()
    if not s_ok:is_ok() or s_ok:is_err() then
        C.printf("FAIL: status.ok is not ok\n")
        return 1
    end
    var s_err = status.err(status.TABLE_NOT_FOUND, "Table 'users' does not exist")
    if not s_err:is_err() or s_err:get_code() ~= status.TABLE_NOT_FOUND then
        C.printf("FAIL: status.err check failed\n")
        return 1
    end
    C.printf("PASS: Structured status and error codes\n")

    -- Test 6: High resolution stopwatch
    var sw : timer.Stopwatch
    sw:start()
    C.usleep(1000) -- sleep 1ms
    sw:stop()
    var elapsed_us = sw:elapsed_us()
    if elapsed_us < 500.0 then
        C.printf("FAIL: elapsed time unrealistically small: %f us\n", elapsed_us)
        return 1
    end
    C.printf("PASS: High-resolution monotonic stopwatch (%f us)\n", elapsed_us)

    -- Test 7: SIMD vector operations
    var a : float[8]
    var b : float[8]
    for i = 0, 8 do
        a[i] = [float](i + 1)
        b[i] = [float]((i + 1) * 2)
    end
    var dot = simd.dot_product_f32(&(a[0]), &(b[0]), 8)
    if C.fabs([double](dot - 408.0f)) > 0.001 then
        C.printf("FAIL: SIMD dot product expected 408, got %f\n", dot)
        return 1
    end
    var sum = simd.sum_array_f32(&(a[0]), 8)
    if C.fabs([double](sum - 36.0f)) > 0.001 then
        C.printf("FAIL: SIMD sum array expected 36, got %f\n", sum)
        return 1
    end
    C.printf("PASS: SIMD 4-wide vector dot product and reduction\n")

    C.printf("=== ALL COMMON TESTS PASSED (7/7) ===\n")
    return 0
end

local code = run_common_tests()
if code ~= 0 then
    os.exit(1)
end
