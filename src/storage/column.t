-- Quarry columnar buffer subsystem
-- Contiguous typed column vectors with 64-byte alignment and prefix-cached string views.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local null_mask = require("src.storage/null_mask")

local col = {}

-- German / Umbra style 16-byte string view:
-- len (4 bytes), prefix (4 bytes for instant branchless prefix equality), ptr (8 bytes)
struct StringView {
    len: uint32,
    prefix: int8[4],
    ptr: &int8
}

terra StringView:set(s: &int8, arena: &alloc.Arena)
    if s == nil then
        self.len = 0
        C.memset(&(self.prefix[0]), 0, 4)
        self.ptr = nil
        return
    end

    var slen = [uint32](C.strlen(s))
    self.len = slen

    -- Copy up to 4 bytes into inline prefix
    C.memset(&(self.prefix[0]), 0, 4)
    var pcount = slen
    if pcount > 4 then pcount = 4 end
    for i = 0, pcount do
        self.prefix[i] = s[i]
    end

    if arena ~= nil then
        var copy_ptr = [&int8](arena:allocate(slen + 1, 1))
        C.memcpy(copy_ptr, s, slen)
        copy_ptr[slen] = 0
        self.ptr = copy_ptr
    else
        self.ptr = s
    end
end

terra StringView:as_cstring() : &int8
    if self.ptr ~= nil then
        return self.ptr
    end
    return ""
end

struct ColumnVector {
    data_type: types.DataType,
    capacity: uint32,
    count: uint32,
    validity: null_mask.ValidityMask,
    raw_data: &uint8,
    string_arena: alloc.Arena
}

terra ColumnVector:init(dt: types.DataType, capacity: uint32)
    self.data_type = dt
    self.capacity = capacity
    self.count = 0
    self.validity:init(capacity)
    self.string_arena:init(32768)

    var byte_width = dt.byte_width
    if byte_width == 0 then byte_width = 8 end
    var total_bytes = capacity * byte_width
    self.raw_data = [&uint8](alloc.aligned_alloc(total_bytes, alloc.CACHE_LINE))
    C.memset(self.raw_data, 0, total_bytes)
end

terra ColumnVector:destroy()
    self.validity:destroy()
    self.string_arena:destroy()
    if self.raw_data ~= nil then
        alloc.aligned_free(self.raw_data)
        self.raw_data = nil
    end
    self.capacity = 0
    self.count = 0
end

terra ColumnVector:reset()
    self.count = 0
    self.validity:set_all_valid()
    self.string_arena:reset()
end

-- Typed setters
terra ColumnVector:set_i64(row: uint32, val: int64)
    if row >= self.capacity then return end
    var ptr = [&int64](self.raw_data)
    ptr[row] = val
    self.validity:set_valid(row)
    if row >= self.count then self.count = row + 1 end
end

terra ColumnVector:set_i32(row: uint32, val: int32)
    if row >= self.capacity then return end
    var ptr = [&int32](self.raw_data)
    ptr[row] = val
    self.validity:set_valid(row)
    if row >= self.count then self.count = row + 1 end
end

terra ColumnVector:set_f64(row: uint32, val: double)
    if row >= self.capacity then return end
    var ptr = [&double](self.raw_data)
    ptr[row] = val
    self.validity:set_valid(row)
    if row >= self.count then self.count = row + 1 end
end

terra ColumnVector:set_f32(row: uint32, val: float)
    if row >= self.capacity then return end
    var ptr = [&float](self.raw_data)
    ptr[row] = val
    self.validity:set_valid(row)
    if row >= self.count then self.count = row + 1 end
end

terra ColumnVector:set_bool(row: uint32, val: bool)
    if row >= self.capacity then return end
    var ptr = [&bool](self.raw_data)
    ptr[row] = val
    self.validity:set_valid(row)
    if row >= self.count then self.count = row + 1 end
end

terra ColumnVector:set_string(row: uint32, s: &int8)
    if row >= self.capacity then return end
    var sv_ptr = [&StringView](self.raw_data)
    sv_ptr[row]:set(s, &(self.string_arena))
    self.validity:set_valid(row)
    if row >= self.count then self.count = row + 1 end
end

terra ColumnVector:set_vector(row: uint32, vec_data: &float, dim: uint32)
    if row >= self.capacity then return end
    var stride = self.data_type.vector_dim
    var ptr = [&float](self.raw_data)
    var target = &(ptr[row * stride])
    C.memcpy(target, vec_data, dim * sizeof(float))
    self.validity:set_valid(row)
    if row >= self.count then self.count = row + 1 end
end

terra ColumnVector:set_null(row: uint32)
    if row >= self.capacity then return end
    self.validity:set_null(row)
    if row >= self.count then self.count = row + 1 end
end

-- Typed getters
terra ColumnVector:get_i64(row: uint32) : int64
    if self.data_type.type_id == types.INT32 then
        var ptr = [&int32](self.raw_data)
        return [int64](ptr[row])
    elseif self.data_type.type_id == types.DOUBLE then
        var ptr = [&double](self.raw_data)
        return [int64](ptr[row])
    else
        var ptr = [&int64](self.raw_data)
        return ptr[row]
    end
end

terra ColumnVector:get_i32(row: uint32) : int32
    var ptr = [&int32](self.raw_data)
    return ptr[row]
end

terra ColumnVector:get_f64(row: uint32) : double
    if self.data_type.type_id == types.FLOAT then
        var ptr = [&float](self.raw_data)
        return [double](ptr[row])
    elseif self.data_type.type_id == types.INT64 or self.data_type.type_id == types.INT32 then
        return [double](self:get_i64(row))
    else
        var ptr = [&double](self.raw_data)
        return ptr[row]
    end
end

terra ColumnVector:get_f32(row: uint32) : float
    var ptr = [&float](self.raw_data)
    return ptr[row]
end

terra ColumnVector:get_bool(row: uint32) : bool
    var ptr = [&bool](self.raw_data)
    return ptr[row]
end

terra ColumnVector:get_string(row: uint32) : &int8
    var sv_ptr = [&StringView](self.raw_data)
    return sv_ptr[row]:as_cstring()
end

terra ColumnVector:get_vector(row: uint32) : &float
    var stride = self.data_type.vector_dim
    var ptr = [&float](self.raw_data)
    return &(ptr[row * stride])
end

terra ColumnVector:is_null(row: uint32) : bool
    return self.validity:is_null(row)
end

col.StringView = StringView
col.ColumnVector = ColumnVector
return col
