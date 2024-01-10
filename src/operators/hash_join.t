-- Quarry physical vectorized hash join operator
-- Open-addressing hash table with linear probing and MurmurHash3 key mixing.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local hash = require("src.common.hash")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk

local join = {}

struct HashJoinEntry {
    key: int64,
    payload_val: int64,
    is_occupied: bool
}

struct PhysicalHashJoin {
    capacity: uint32,
    mask: uint32,
    count: uint32,
    entries: &HashJoinEntry,
    build_key_col: uint32,
    build_val_col: uint32,
    probe_key_col: uint32,
    is_left_join: bool
}

terra PhysicalHashJoin:init(capacity: uint32, build_key: uint32, build_val: uint32, probe_key: uint32, is_left: bool)
    var cap = capacity
    if cap < 16 then cap = 16 end
    -- Round up to next power of 2
    var v = cap - 1
    v = v or (v >> 1)
    v = v or (v >> 2)
    v = v or (v >> 4)
    v = v or (v >> 8)
    v = v or (v >> 16)
    self.capacity = v + 1
    self.mask = self.capacity - 1
    self.count = 0

    self.entries = [&HashJoinEntry](alloc.aligned_alloc(self.capacity * sizeof(HashJoinEntry), alloc.CACHE_LINE))
    C.memset(self.entries, 0, self.capacity * sizeof(HashJoinEntry))

    self.build_key_col = build_key
    self.build_val_col = build_val
    self.probe_key_col = probe_key
    self.is_left_join = is_left
end

terra PhysicalHashJoin:destroy()
    if self.entries ~= nil then
        alloc.aligned_free(self.entries)
        self.entries = nil
    end
    self.capacity = 0
    self.count = 0
end

-- Build phase: insert (key, payload) into hash table with linear probing
terra PhysicalHashJoin:insert(k: int64, payload: int64) : bool
    if self.count * 2 >= self.capacity then
        return false -- Load factor >= 0.5
    end

    var h = [uint32](hash.hash_u64([uint64](k)))
    var slot = h and self.mask

    while self.entries[slot].is_occupied do
        slot = (slot + 1) and self.mask
    end

    self.entries[slot].key = k
    self.entries[slot].payload_val = payload
    self.entries[slot].is_occupied = true
    self.count = self.count + 1
    return true
end

-- Probe phase: lookup key in hash table
terra PhysicalHashJoin:lookup(k: int64, out_val: &int64) : bool
    var h = [uint32](hash.hash_u64([uint64](k)))
    var slot = h and self.mask

    while self.entries[slot].is_occupied do
        if self.entries[slot].key == k then
            @out_val = self.entries[slot].payload_val
            return true
        end
        slot = (slot + 1) and self.mask
    end

    return false
end

-- Build all rows from build_chunk into hash table
terra PhysicalHashJoin:build(build_chunk: &DataChunk)
    var key_col = build_chunk:get_column(self.build_key_col)
    var val_col = build_chunk:get_column(self.build_val_col)
    var n = build_chunk.num_rows

    for i = 0, n do
        var phys_idx = build_chunk:get_row_index(i)
        if not key_col:is_null(phys_idx) then
            var k = key_col:get_i64(phys_idx)
            var v : int64 = 0
            if val_col ~= nil and not val_col:is_null(phys_idx) then
                v = val_col:get_i64(phys_idx)
            end
            self:insert(k, v)
        end
    end
end

-- Probe input_chunk and populate output_chunk with joined rows
terra PhysicalHashJoin:probe(probe_chunk: &DataChunk, out_chunk: &DataChunk) : uint32
    var probe_col = probe_chunk:get_column(self.probe_key_col)
    var out_matched : uint32 = 0
    var n = probe_chunk.num_rows

    var out_left_col = out_chunk:get_column(0)
    var out_right_col = out_chunk:get_column(1)

    for i = 0, n do
        var phys_idx = probe_chunk:get_row_index(i)
        if not probe_col:is_null(phys_idx) then
            var k = probe_col:get_i64(phys_idx)
            var matched_val : int64 = 0
            var found = self:lookup(k, &matched_val)

            if found then
                out_left_col:set_i64(out_matched, k)
                out_right_col:set_i64(out_matched, matched_val)
                out_matched = out_matched + 1
            elseif self.is_left_join then
                out_left_col:set_i64(out_matched, k)
                out_right_col:set_null(out_matched)
                out_matched = out_matched + 1
            end
        end
    end

    out_chunk.num_rows = out_matched
    out_chunk.has_selection = false
    return out_matched
end

join.HashJoinEntry = HashJoinEntry
join.PhysicalHashJoin = PhysicalHashJoin
return join
