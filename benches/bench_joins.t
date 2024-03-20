-- bench_joins.t
-- Micro-benchmark evaluating vectorized hash join build and probe throughput
-- with open-addressing hash table across 500,000 keys and 1,000,000 probe tuples.

local C = require("src.common.c").C
local timer = require("src.common.timer")
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local join = require("src.operators/hash_join")

local DataChunk = chunk.DataChunk

local BUILD_SIZE = 500000
local PROBE_SIZE = 1000000

local terra run_join_bench() : int
    C.printf("=================================================================\n")
    C.printf("  QUARRY HASH JOIN BENCHMARK (Build: %d, Probe: %d)\n", BUILD_SIZE, PROBE_SIZE)
    C.printf("=================================================================\n")

    -- 1. Populate Build Chunk
    var build_chunk : DataChunk
    var b_types : types.DataType[2]
    b_types[0] = types.make_type(types.INT64, 0)
    b_types[1] = types.make_type(types.INT64, 0)
    build_chunk:init(2, &(b_types[0]), BUILD_SIZE)

    for i = 0, BUILD_SIZE do
        build_chunk.columns[0]:set_i64(i, [int64](i * 2)) -- even keys: 0, 2, 4, ...
        build_chunk.columns[1]:set_i64(i, [int64](i * 10))
    end
    build_chunk.num_rows = BUILD_SIZE

    -- 2. Build Hash Table
    var hash_op : join.PhysicalHashJoin
    hash_op:init(BUILD_SIZE * 2, 0, 1, 1, false)

    var sw_build : timer.Stopwatch
    sw_build:start()
    hash_op:build(&build_chunk)
    sw_build:stop()
    var build_us = sw_build:elapsed_us()
    var build_m_keys_sec = [double](BUILD_SIZE) / [double](build_us)

    -- 3. Populate Probe Chunk
    var probe_chunk : DataChunk
    var p_types : types.DataType[2]
    p_types[0] = types.make_type(types.INT64, 0)
    p_types[1] = types.make_type(types.INT64, 0)
    probe_chunk:init(2, &(p_types[0]), PROBE_SIZE)

    for i = 0, PROBE_SIZE do
        probe_chunk.columns[0]:set_i64(i, [int64](i))
        probe_chunk.columns[1]:set_i64(i, [int64](i)) -- 50% hit rate (even keys match)
    end
    probe_chunk.num_rows = PROBE_SIZE

    -- 4. Probe Hash Table
    var out_chunk : DataChunk
    out_chunk:init(2, &(p_types[0]), PROBE_SIZE)

    var sw_probe : timer.Stopwatch
    sw_probe:start()
    var matched_rows = hash_op:probe(&probe_chunk, &out_chunk)
    sw_probe:stop()
    var probe_us = sw_probe:elapsed_us()
    var probe_m_keys_sec = [double](PROBE_SIZE) / [double](probe_us)

    C.printf("Phase        | Tuples    | Time (us) | Throughput (M keys/s) | Matches\n")
    C.printf("-------------|-----------|-----------|-----------------------|-----------\n")
    C.printf("Hash Build   | %9d | %9.1f | %21.2f | %d\n", BUILD_SIZE, build_us, build_m_keys_sec, BUILD_SIZE)
    C.printf("Hash Probe   | %9d | %9.1f | %21.2f | %u\n", PROBE_SIZE, probe_us, probe_m_keys_sec, matched_rows)
    C.printf("-----------------------------------------------------------------\n")
    C.printf("Hit Rate: %.1f%% (Expected 50.0%%)\n", ([double](matched_rows) / [double](PROBE_SIZE)) * 100.0)
    C.printf("=================================================================\n")

    build_chunk:destroy()
    probe_chunk:destroy()
    out_chunk:destroy()
    hash_op:destroy()
    return 0
end

local code = run_join_bench()
if code ~= 0 then os.exit(1) end
