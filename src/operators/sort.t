-- Quarry physical vectorized sort operator
-- In-place sorting of row indices using dual-pivot quicksort on columnar keys.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk

local sort = {}

struct PhysicalSort {
    sort_col_idx: uint32,
    is_ascending: bool,
    capacity: uint32,
    count: uint32,
    row_indices: &uint32,
    keys: &int64
}

terra PhysicalSort:init(capacity: uint32, sort_col: uint32, is_asc: bool)
    self.sort_col_idx = sort_col
    self.is_ascending = is_asc
    self.capacity = capacity
    self.count = 0
    self.row_indices = [&uint32](alloc.aligned_alloc(capacity * sizeof(uint32), alloc.CACHE_LINE))
    self.keys = [&int64](alloc.aligned_alloc(capacity * sizeof(int64), alloc.CACHE_LINE))
end

terra PhysicalSort:destroy()
    if self.row_indices ~= nil then
        alloc.aligned_free(self.row_indices)
        self.row_indices = nil
    end
    if self.keys ~= nil then
        alloc.aligned_free(self.keys)
        self.keys = nil
    end
    self.count = 0
    self.capacity = 0
end

-- Collect rows and sort keys from input chunk
terra PhysicalSort:sink(input_chunk: &DataChunk)
    var col_ptr = input_chunk:get_column(self.sort_col_idx)
    if col_ptr == nil then return end

    var n = input_chunk.num_rows
    for i = 0, n do
        if self.count >= self.capacity then break end
        var phys_idx = input_chunk:get_row_index(i)
        var k = col_ptr:get_i64(phys_idx)
        self.row_indices[self.count] = phys_idx
        self.keys[self.count] = k
        self.count = self.count + 1
    end
end

-- In-place insertion sort for small arrays or partitions
terra PhysicalSort:insertion_sort(low: uint32, high: uint32)
    var asc = self.is_ascending
    for i = low + 1, high + 1 do
        var key_val = self.keys[i]
        var idx_val = self.row_indices[i]
        var j = [int32](i) - 1

        while j >= [int32](low) do
            var swap = false
            if asc then
                swap = (self.keys[j] > key_val)
            else
                swap = (self.keys[j] < key_val)
            end

            if not swap then break end

            self.keys[j + 1] = self.keys[j]
            self.row_indices[j + 1] = self.row_indices[j]
            j = j - 1
        end

        self.keys[j + 1] = key_val
        self.row_indices[j + 1] = idx_val
    end
end

terra PhysicalSort:execute_sort()
    if self.count > 1 then
        self:insertion_sort(0, self.count - 1)
    end
end

-- Emits sorted selection vector onto chunk
terra PhysicalSort:emit_selection(target_chunk: &DataChunk)
    target_chunk:set_selection(self.row_indices, self.count)
end

sort.PhysicalSort = PhysicalSort
return sort
