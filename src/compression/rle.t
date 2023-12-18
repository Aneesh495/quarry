-- Quarry Run-Length Encoding (RLE) subsystem
-- Compresses low-cardinality repetitive columnar sequences with direct predicate evaluation.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")

local rle = {}

struct RunPair {
    val: int64,
    length: uint32
}

struct CompressedRleBlock {
    total_elements: uint32,
    num_runs: uint32,
    capacity: uint32,
    runs: &RunPair
}

terra CompressedRleBlock:init()
    self.total_elements = 0
    self.num_runs = 0
    self.capacity = 16
    self.runs = [&RunPair](C.malloc(self.capacity * sizeof(RunPair)))
end

terra CompressedRleBlock:destroy()
    if self.runs ~= nil then
        C.free(self.runs)
        self.runs = nil
    end
    self.total_elements = 0
    self.num_runs = 0
    self.capacity = 0
end

terra CompressedRleBlock:compress(src: &int64, count: uint32)
    if count == 0 then return end
    self.total_elements = count
    self.num_runs = 0

    var current_val = src[0]
    var current_len : uint32 = 1

    for i = 1, count do
        if src[i] == current_val then
            current_len = current_len + 1
        else
            -- Push completed run
            if self.num_runs >= self.capacity then
                self.capacity = self.capacity * 2
                self.runs = [&RunPair](C.realloc(self.runs, self.capacity * sizeof(RunPair)))
            end
            self.runs[self.num_runs].val = current_val
            self.runs[self.num_runs].length = current_len
            self.num_runs = self.num_runs + 1

            current_val = src[i]
            current_len = 1
        end
    end

    -- Push final run
    if self.num_runs >= self.capacity then
        self.capacity = self.capacity * 2
        self.runs = [&RunPair](C.realloc(self.runs, self.capacity * sizeof(RunPair)))
    end
    self.runs[self.num_runs].val = current_val
    self.runs[self.num_runs].length = current_len
    self.num_runs = self.num_runs + 1
end

terra CompressedRleBlock:decompress(dst: &int64)
    var out_idx : uint32 = 0
    for r = 0, self.num_runs do
        var v = self.runs[r].val
        var len = self.runs[r].length
        for i = 0, len do
            dst[out_idx] = v
            out_idx = out_idx + 1
        end
    end
end

-- Direct filter pushdown: populates selection vector with row indices where val == target
terra CompressedRleBlock:filter_equal(target: int64, out_selection: &uint32) : uint32
    var matched_count : uint32 = 0
    var current_row : uint32 = 0

    for r = 0, self.num_runs do
        var v = self.runs[r].val
        var len = self.runs[r].length

        if v == target then
            -- Match: add all row indices in this run to selection vector
            for i = 0, len do
                out_selection[matched_count] = current_row + i
                matched_count = matched_count + 1
            end
        end

        current_row = current_row + len
    end

    return matched_count
end

rle.RunPair = RunPair
rle.CompressedRleBlock = CompressedRleBlock
return rle
