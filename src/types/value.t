-- Quarry dynamic scalar value representation
-- Tagged union holding typed primitives, strings, and vector references.

local C = require("src.common.c").C
local types = require("src.types.type")

local value = {}

struct Value {
    type_id: int32,
    is_null: bool,
    vector_dim: uint32,
    union {
        val_bool: bool,
        val_i64: int64,
        val_u64: uint64,
        val_f64: double,
        val_f32: float,
        val_str: int8[64],
        val_ptr: &opaque
    }
}

terra Value:init_null(tid: int32)
    self.type_id = tid
    self.is_null = true
    self.vector_dim = 0
    self.val_i64 = 0
end

terra Value:init_bool(b: bool)
    self.type_id = types.BOOL
    self.is_null = false
    self.vector_dim = 0
    self.val_bool = b
end

terra Value:init_i64(tid: int32, v: int64)
    self.type_id = tid
    self.is_null = false
    self.vector_dim = 0
    self.val_i64 = v
end

terra Value:init_f64(v: double)
    self.type_id = types.DOUBLE
    self.is_null = false
    self.vector_dim = 0
    self.val_f64 = v
end

terra Value:init_f32(v: float)
    self.type_id = types.FLOAT
    self.is_null = false
    self.vector_dim = 0
    self.val_f32 = v
end

terra Value:init_string(s: &int8)
    self.type_id = types.VARCHAR
    self.is_null = false
    self.vector_dim = 0
    if s ~= nil then
        C.strncpy(&(self.val_str[0]), s, 63)
        self.val_str[63] = 0
    else
        self.val_str[0] = 0
    end
end

terra Value:init_vector(vec_data: &float, dim: uint32)
    self.type_id = types.VECTOR_F32
    self.is_null = false
    self.vector_dim = dim
    self.val_ptr = [&opaque](vec_data)
end

terra Value:as_i64() : int64
    if self.type_id == types.DOUBLE then
        return [int64](self.val_f64)
    elseif self.type_id == types.FLOAT then
        return [int64](self.val_f32)
    elseif self.type_id == types.BOOL then
        if self.val_bool then return 1 else return 0 end
    else
        return self.val_i64
    end
end

terra Value:as_f64() : double
    if self.type_id == types.DOUBLE then
        return self.val_f64
    elseif self.type_id == types.FLOAT then
        return [double](self.val_f32)
    elseif self.type_id == types.BOOL then
        if self.val_bool then return 1.0 else return 0.0 end
    else
        return [double](self.val_i64)
    end
end

terra Value:as_string() : &int8
    if self.type_id == types.VARCHAR then
        return &(self.val_str[0])
    end
    return ""
end

terra Value:compare(other: &Value) : int32
    if self.is_null and other.is_null then return 0 end
    if self.is_null then return -1 end
    if other.is_null then return 1 end

    if self.type_id == types.VARCHAR or other.type_id == types.VARCHAR then
        var s1 = self:as_string()
        var s2 = other:as_string()
        var cmp = C.strcmp(s1, s2)
        if cmp < 0 then return -1 elseif cmp > 0 then return 1 else return 0 end
    elseif self.type_id == types.DOUBLE or other.type_id == types.DOUBLE or
           self.type_id == types.FLOAT or other.type_id == types.FLOAT then
        var d1 = self:as_f64()
        var d2 = other:as_f64()
        if d1 < d2 then return -1 elseif d1 > d2 then return 1 else return 0 end
    else
        var i1 = self:as_i64()
        var i2 = other:as_i64()
        if i1 < i2 then return -1 elseif i1 > i2 then return 1 else return 0 end
    end
end

terra Value:equals(other: &Value) : bool
    return self:compare(other) == 0
end

terra Value:format(buf: &int8, max_len: C.size_t) : int32
    if self.is_null then
        return C.snprintf(buf, max_len, "NULL")
    end

    var tid = self.type_id
    if tid == types.BOOL then
        if self.val_bool then
            return C.snprintf(buf, max_len, "true")
        else
            return C.snprintf(buf, max_len, "false")
        end
    elseif tid >= types.INT8 and tid <= types.INT64 then
        return C.snprintf(buf, max_len, "%lld", self.val_i64)
    elseif tid >= types.UINT8 and tid <= types.UINT64 then
        return C.snprintf(buf, max_len, "%llu", self.val_u64)
    elseif tid == types.FLOAT then
        return C.snprintf(buf, max_len, "%f", [double](self.val_f32))
    elseif tid == types.DOUBLE then
        return C.snprintf(buf, max_len, "%f", self.val_f64)
    elseif tid == types.VARCHAR then
        return C.snprintf(buf, max_len, "%s", &(self.val_str[0]))
    elseif tid == types.VECTOR_F32 then
        var vec_ptr = [&float](self.val_ptr)
        var offset = C.snprintf(buf, max_len, "[")
        var dim = self.vector_dim
        if dim > 8 then dim = 8 end
        for i = 0, dim do
            if i > 0 then
                offset = offset + C.snprintf(buf + offset, max_len - offset, ", ")
            end
            offset = offset + C.snprintf(buf + offset, max_len - offset, "%.3f", vec_ptr[i])
        end
        if self.vector_dim > 8 then
            offset = offset + C.snprintf(buf + offset, max_len - offset, ", ... +%d more", self.vector_dim - 8)
        end
        offset = offset + C.snprintf(buf + offset, max_len - offset, "]")
        return offset
    else
        return C.snprintf(buf, max_len, "?")
    end
end

local terra make_null_fn(tid: int32) : Value
    var v : Value
    v:init_null(tid)
    return v
end

local terra make_i64_fn(v: int64) : Value
    var val : Value
    val:init_i64(types.INT64, v)
    return val
end

local terra make_f64_fn(v: double) : Value
    var val : Value
    val:init_f64(v)
    return val
end

local terra make_bool_fn(b: bool) : Value
    var val : Value
    val:init_bool(b)
    return val
end

local terra make_string_fn(s: &int8) : Value
    var val : Value
    val:init_string(s)
    return val
end

local terra make_vector_fn(vec_data: &float, dim: uint32) : Value
    var val : Value
    val:init_vector(vec_data, dim)
    return val
end

value.Value = Value
value.make_null = make_null_fn
value.make_i64 = make_i64_fn
value.make_f64 = make_f64_fn
value.make_bool = make_bool_fn
value.make_string = make_string_fn
value.make_vector = make_vector_fn

return value
