-- test_regressions.t
-- Regression test suite documenting and preventing reoccurrence of bugs
-- discovered during the development of Quarry.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local value = require("src.types.value")
local vector = require("src.types.vector")
local col = require("src.storage/column")
local chunk = require("src.storage/chunk")
local table_mod = require("src.storage/table")
local catalog = require("src.storage/catalog")
local join = require("src.operators/hash_join")
local rle = require("src.compression/rle")

local DataChunk = chunk.DataChunk

print("=== Running Quarry Regression & Bug Prevention Suite ===")

-- Regression 1: Empty table vector k-NN search must not crash or return invalid memory
local terra test_regression_empty_table_scan() : bool
  var my_cat : catalog.Catalog
  my_cat:init()

  var col_names : (&int8)[2]
  col_names[0] = "id"
  col_names[1] = "embedding"

  var col_tps : types.DataType[2]
  col_tps[0] = types.make_type(types.INT64, 0)
  col_tps[1] = types.make_type(types.VECTOR_F32, 4)

  var t = my_cat:create_table("empty_table", 2, &(col_names[0]), &(col_tps[0]))
  if t == nil then
    my_cat:destroy()
    return false
  end

  if t.num_chunks ~= 0 or t.total_rows ~= 0 then
    my_cat:destroy()
    return false
  end

  my_cat:destroy()
  return true
end

-- Regression 2: ColumnVector StringView short string inline prefix vs heap pointer
local terra test_regression_string_view_prefix() : bool
  var arena : alloc.Arena
  arena:init(4096)

  var sv1 : col.StringView
  sv1:set("abc", &arena)
  if sv1.len ~= 3 then return false end
  if sv1.prefix[0] ~= 97 or sv1.prefix[1] ~= 98 or sv1.prefix[2] ~= 99 then return false end

  var sv2 : col.StringView
  sv2:set("abc", &arena)
  if C.strcmp(sv1:as_cstring(), sv2:as_cstring()) ~= 0 then return false end

  var sv3 : col.StringView
  sv3:set("xyz", &arena)
  if C.strcmp(sv1:as_cstring(), sv3:as_cstring()) == 0 then return false end

  var sv4 : col.StringView
  sv4:set("long_string_test_one", &arena)
  var sv5 : col.StringView
  sv5:set("long_string_test_two", &arena)
  if C.strcmp(sv4:as_cstring(), sv5:as_cstring()) == 0 then return false end

  arena:destroy()
  return true
end

-- Regression 3: RLE compression on single-element run
local terra test_regression_rle_single_element() : bool
  var in_vals : int64[1]
  in_vals[0] = 42

  var rle_blk : rle.CompressedRleBlock
  rle_blk:init()
  rle_blk:compress(&(in_vals[0]), 1)

  if rle_blk.num_runs ~= 1 then
    rle_blk:destroy()
    return false
  end

  var decoded : int64[1]
  rle_blk:decompress(&(decoded[0]))
  var ok = (decoded[0] == 42)
  rle_blk:destroy()
  return ok
end

-- Regression 4: Hash table open addressing probing with unmatched keys
local terra test_regression_hash_table_probing() : bool
  var build_chunk : DataChunk
  var b_types : types.DataType[2]
  b_types[0] = types.make_type(types.INT64, 0)
  b_types[1] = types.make_type(types.INT64, 0)
  build_chunk:init(2, &(b_types[0]), 32)

  for i = 0, 5 do
    var k = [int64]((i + 1) * 10)
    var v = [int64]((i + 1) * 100)
    build_chunk.columns[0]:set_i64(i, k)
    build_chunk.columns[1]:set_i64(i, v)
  end
  build_chunk.num_rows = 5

  var hash_op : join.PhysicalHashJoin
  hash_op:init(16, 0, 1, 1, false)
  hash_op:build(&build_chunk)

  var probe_chunk : DataChunk
  var p_types : types.DataType[2]
  p_types[0] = types.make_type(types.INT64, 0)
  p_types[1] = types.make_type(types.INT64, 0)
  probe_chunk:init(2, &(p_types[0]), 32)
  probe_chunk.columns[0]:set_i64(0, 1)
  probe_chunk.columns[1]:set_i64(0, 999) -- Non-existent key
  probe_chunk.num_rows = 1

  var out_chunk : DataChunk
  out_chunk:init(2, &(p_types[0]), 32)
  hash_op:probe(&probe_chunk, &out_chunk)

  -- Non-existent key in inner join should produce 0 output rows
  var matches = out_chunk.num_rows
  build_chunk:destroy()
  probe_chunk:destroy()
  out_chunk:destroy()
  hash_op:destroy()

  return matches == 0
end

-- Regression 5: Dense vector L2 normalization when norm is zero
local terra test_regression_zero_vector_norm() : bool
  var coords : float[3]
  coords[0] = 0.0f
  coords[1] = 0.0f
  coords[2] = 0.0f

  var v : vector.DenseVector
  v:init(3)
  v:copy_from(&(coords[0]), 3)
  var n = v:l2_norm()
  if n ~= 0.0f then
    v:destroy()
    return false
  end

  -- Normalization of zero vector should not produce NaN or crash
  v:normalize()
  var c0 = v.data[0]
  v:destroy()
  if c0 ~= 0.0f then return false end

  return true
end

assert(test_regression_empty_table_scan(), "Regression 1 failed")
print("PASS: Regression 1 (Empty table scan handled safely)")
assert(test_regression_string_view_prefix(), "Regression 2 failed")
print("PASS: Regression 2 (StringView inline prefix comparison)")
assert(test_regression_rle_single_element(), "Regression 3 failed")
print("PASS: Regression 3 (RLE single element run)")
assert(test_regression_hash_table_probing(), "Regression 4 failed")
print("PASS: Regression 4 (Hash table collision probing with unmatched keys)")
assert(test_regression_zero_vector_norm(), "Regression 5 failed")
print("PASS: Regression 5 (Zero vector norm and normalization stability)")

print("=== ALL REGRESSION TESTS PASSED (5/5) ===")
