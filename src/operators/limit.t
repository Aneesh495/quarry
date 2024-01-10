-- Quarry physical limit operator
-- Early-stopping limit and offset operator for pipeline short-circuiting.

local C = require("src.common.c").C
local chunk = require("src.storage/chunk")

local DataChunk = chunk.DataChunk

local limit = {}

struct PhysicalLimit {
    limit_val: int64,
    offset_val: int64,
    current_offset: int64,
    current_emitted: int64,
    is_done: bool,
    temp_sel: uint32[2048]
}

terra PhysicalLimit:init(limit_v: int64, offset_v: int64)
    self.limit_val = limit_v
    self.offset_val = offset_v
    self.current_offset = 0
    self.current_emitted = 0
    self.is_done = false
end

terra PhysicalLimit:apply(c: &DataChunk) : bool
    if self.is_done then
        c.num_rows = 0
        return true
    end

    var n = c.num_rows
    var kept_count : uint32 = 0

    for i = 0, n do
        var phys_idx = c:get_row_index(i)

        -- Skip offset rows
        if self.current_offset < self.offset_val then
            self.current_offset = self.current_offset + 1
        elseif self.limit_val < 0 or self.current_emitted < self.limit_val then
            self.temp_sel[kept_count] = phys_idx
            kept_count = kept_count + 1
            self.current_emitted = self.current_emitted + 1
            if self.limit_val >= 0 and self.current_emitted >= self.limit_val then
                self.is_done = true
                break
            end
        end
    end

    c:set_selection(&(self.temp_sel[0]), kept_count)
    return self.is_done
end

limit.PhysicalLimit = PhysicalLimit
return limit
