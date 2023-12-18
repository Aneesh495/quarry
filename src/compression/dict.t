-- Quarry dictionary encoding subsystem
-- Encodes low-cardinality strings and integers into compact 8-bit or 16-bit code streams.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")

local dict = {}

dict.MAX_DICT_ENTRIES = 256

struct DictEntry {
    str: int8[64],
    len: uint32
}

struct CompressedDictBlock {
    total_elements: uint32,
    num_entries: uint32,
    entries: DictEntry[256],
    codes: &uint8
}

terra CompressedDictBlock:init()
    self.total_elements = 0
    self.num_entries = 0
    self.codes = nil
end

terra CompressedDictBlock:destroy()
    if self.codes ~= nil then
        alloc.aligned_free(self.codes)
        self.codes = nil
    end
    self.total_elements = 0
    self.num_entries = 0
end

terra CompressedDictBlock:find_or_add_entry(s: &int8) : int32
    if s == nil then return -1 end
    for i = 0, self.num_entries do
        if C.strcmp(&(self.entries[i].str[0]), s) == 0 then
            return [int32](i)
        end
    end

    if self.num_entries >= dict.MAX_DICT_ENTRIES then
        return -1 -- Dictionary overflow
    end

    var idx = self.num_entries
    C.strncpy(&(self.entries[idx].str[0]), s, 63)
    self.entries[idx].str[63] = 0
    self.entries[idx].len = [uint32](C.strlen(s))
    self.num_entries = self.num_entries + 1
    return [int32](idx)
end

terra CompressedDictBlock:find_code(s: &int8) : int32
    if s == nil then return -1 end
    for i = 0, self.num_entries do
        if C.strcmp(&(self.entries[i].str[0]), s) == 0 then
            return [int32](i)
        end
    end
    return -1
end

terra CompressedDictBlock:compress_strings(strings: &(&int8), count: uint32) : bool
    self.total_elements = count
    self.num_entries = 0
    self.codes = [&uint8](alloc.aligned_alloc(count * sizeof(uint8), alloc.CACHE_LINE))

    for i = 0, count do
        var code = self:find_or_add_entry(strings[i])
        if code < 0 then
            return false -- Cardinality exceeded 256
        end
        self.codes[i] = [uint8](code)
    end

    return true
end

terra CompressedDictBlock:decompress_string(idx: uint32) : &int8
    if idx >= self.total_elements or self.codes == nil then return "" end
    var code = self.codes[idx]
    if code >= self.num_entries then return "" end
    return &(self.entries[code].str[0])
end

-- Direct filter pushdown: matches target string by finding its 8-bit dictionary code first
terra CompressedDictBlock:filter_equal(target: &int8, out_selection: &uint32) : uint32
    var target_code = self:find_code(target)
    if target_code < 0 then
        return 0 -- String does not exist in dictionary, zero matches instantly
    end

    var matched_count : uint32 = 0
    var code_val = [uint8](target_code)

    for i = 0, self.total_elements do
        if self.codes[i] == code_val then
            out_selection[matched_count] = i
            matched_count = matched_count + 1
        end
    end

    return matched_count
end

dict.DictEntry = DictEntry
dict.CompressedDictBlock = CompressedDictBlock
return dict
