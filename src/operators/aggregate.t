-- Quarry physical vectorized aggregation operator
-- Hash aggregation for GROUP BY and vectorized scalar reduction accumulators.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local hash = require("src.common.hash")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk

local agg = {}

agg.AGG_SUM   = 1
agg.AGG_COUNT = 2
agg.AGG_AVG   = 3
agg.AGG_MIN   = 4
agg.AGG_MAX   = 5

struct AggEntry {
    group_key: int64,
    count: uint64,
    sum_i64: int64,
    sum_f64: double,
    min_i64: int64,
    max_i64: int64,
    is_occupied: bool
}

struct PhysicalHashAggregate {
    capacity: uint32,
    mask: uint32,
    num_groups: uint32,
    entries: &AggEntry,
    group_col_idx: uint32,
    val_col_idx: uint32,
    has_group_by: bool,
    global_count: uint64,
    global_sum_i64: int64,
    global_sum_f64: double,
    global_min: int64,
    global_max: int64
}

terra PhysicalHashAggregate:init(capacity: uint32, group_col: uint32, val_col: uint32, has_gb: bool)
    var cap = capacity
    if cap < 16 then cap = 16 end
    var v = cap - 1
    v = v or (v >> 1)
    v = v or (v >> 2)
    v = v or (v >> 4)
    v = v or (v >> 8)
    v = v or (v >> 16)
    self.capacity = v + 1
    self.mask = self.capacity - 1
    self.num_groups = 0

    self.entries = [&AggEntry](alloc.aligned_alloc(self.capacity * sizeof(AggEntry), alloc.CACHE_LINE))
    C.memset(self.entries, 0, self.capacity * sizeof(AggEntry))

    self.group_col_idx = group_col
    self.val_col_idx = val_col
    self.has_group_by = has_gb
    self.global_count = 0
    self.global_sum_i64 = 0
    self.global_sum_f64 = 0.0
    self.global_min = 0x7FFFFFFFFFFFFFFFLL
    self.global_max = -0x7FFFFFFFFFFFFFFFLL
end

terra PhysicalHashAggregate:destroy()
    if self.entries ~= nil then
        alloc.aligned_free(self.entries)
        self.entries = nil
    end
    self.capacity = 0
    self.num_groups = 0
end

terra PhysicalHashAggregate:get_or_create_entry(k: int64) : &AggEntry
    var h = [uint32](hash.hash_u64([uint64](k)))
    var slot = h and self.mask

    while self.entries[slot].is_occupied do
        if self.entries[slot].group_key == k then
            return &(self.entries[slot])
        end
        slot = (slot + 1) and self.mask
    end

    self.entries[slot].group_key = k
    self.entries[slot].count = 0
    self.entries[slot].sum_i64 = 0
    self.entries[slot].sum_f64 = 0.0
    self.entries[slot].min_i64 = 0x7FFFFFFFFFFFFFFFLL
    self.entries[slot].max_i64 = -0x7FFFFFFFFFFFFFFFLL
    self.entries[slot].is_occupied = true
    self.num_groups = self.num_groups + 1
    return &(self.entries[slot])
end

terra PhysicalHashAggregate:sink(input_chunk: &DataChunk)
    var n = input_chunk.num_rows
    var val_col = input_chunk:get_column(self.val_col_idx)

    if self.has_group_by then
        var grp_col = input_chunk:get_column(self.group_col_idx)
        for i = 0, n do
            var phys_idx = input_chunk:get_row_index(i)
            if not grp_col:is_null(phys_idx) then
                var k = grp_col:get_i64(phys_idx)
                var entry = self:get_or_create_entry(k)
                entry.count = entry.count + 1

                if val_col ~= nil and not val_col:is_null(phys_idx) then
                    var v = val_col:get_i64(phys_idx)
                    entry.sum_i64 = entry.sum_i64 + v
                    entry.sum_f64 = entry.sum_f64 + [double](v)
                    if v < entry.min_i64 then entry.min_i64 = v end
                    if v > entry.max_i64 then entry.max_i64 = v end
                end
            end
        end
    else
        -- Scalar reduction across the whole chunk
        for i = 0, n do
            var phys_idx = input_chunk:get_row_index(i)
            self.global_count = self.global_count + 1
            if val_col ~= nil and not val_col:is_null(phys_idx) then
                var v = val_col:get_i64(phys_idx)
                self.global_sum_i64 = self.global_sum_i64 + v
                self.global_sum_f64 = self.global_sum_f64 + [double](v)
                if v < self.global_min then self.global_min = v end
                if v > self.global_max then self.global_max = v end
            end
        end
    end
end

-- Emits aggregated groups into output chunk (col 0: group_key, col 1: count, col 2: sum)
terra PhysicalHashAggregate:emit(out_chunk: &DataChunk) : uint32
    var row_count : uint32 = 0

    if self.has_group_by then
        for slot = 0, self.capacity do
            if self.entries[slot].is_occupied then
                out_chunk.columns[0]:set_i64(row_count, self.entries[slot].group_key)
                out_chunk.columns[1]:set_i64(row_count, [int64](self.entries[slot].count))
                out_chunk.columns[2]:set_i64(row_count, self.entries[slot].sum_i64)
                row_count = row_count + 1
                if row_count >= out_chunk.capacity then break end
            end
        end
    else
        out_chunk.columns[0]:set_i64(0, [int64](self.global_count))
        out_chunk.columns[1]:set_i64(0, self.global_sum_i64)
        row_count = 1
    end

    out_chunk.num_rows = row_count
    out_chunk.has_selection = false
    return row_count
end

agg.AggEntry = AggEntry
agg.PhysicalHashAggregate = PhysicalHashAggregate
return agg
