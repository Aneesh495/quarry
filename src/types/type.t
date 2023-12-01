-- Quarry columnar type system
-- Defines physical and logical data types, byte widths, and conversion semantics.

local C = require("src.common.c").C

local types = {}

-- Logical type identifiers
types.BOOL       = 1
types.INT8       = 2
types.INT16      = 3
types.INT32      = 4
types.INT64      = 5
types.UINT8      = 6
types.UINT16     = 7
types.UINT32     = 8
types.UINT64     = 9
types.FLOAT      = 10
types.DOUBLE     = 11
types.VARCHAR    = 12
types.DATE       = 13
types.TIMESTAMP  = 14
types.VECTOR_F32 = 15

struct DataType {
    type_id: int32,
    byte_width: uint32,
    vector_dim: uint32
}

terra DataType:init(tid: int32, dim: uint32)
    self.type_id = tid
    self.vector_dim = dim

    if tid == 1 then -- BOOL
        self.byte_width = 1
    elseif tid == 2 or tid == 6 then -- INT8, UINT8
        self.byte_width = 1
    elseif tid == 3 or tid == 7 then -- INT16, UINT16
        self.byte_width = 2
    elseif tid == 4 or tid == 8 then -- INT32, UINT32
        self.byte_width = 4
    elseif tid == 5 or tid == 9 then -- INT64, UINT64
        self.byte_width = 8
    elseif tid == 10 then -- FLOAT
        self.byte_width = 4
    elseif tid == 11 then -- DOUBLE
        self.byte_width = 8
    elseif tid == 12 then -- VARCHAR (16-byte string header: 4-byte len, 4-byte prefix, 8-byte ptr/offset)
        self.byte_width = 16
    elseif tid == 13 then -- DATE (days since epoch, int32)
        self.byte_width = 4
    elseif tid == 14 then -- TIMESTAMP (microseconds since epoch, int64)
        self.byte_width = 8
    elseif tid == 15 then -- VECTOR_F32 (float32 elements * dimension)
        self.byte_width = dim * 4
    else
        self.byte_width = 0
    end
end

terra DataType:is_numeric() : bool
    var tid = self.type_id
    return (tid >= 2 and tid <= 11)
end

terra DataType:is_integer() : bool
    var tid = self.type_id
    return (tid >= 2 and tid <= 9)
end

terra DataType:is_floating() : bool
    var tid = self.type_id
    return (tid == 10 or tid == 11)
end

terra DataType:is_vector() : bool
    return self.type_id == 15
end

terra DataType:name() : &int8
    var tid = self.type_id
    if tid == 1 then return "BOOLEAN"
    elseif tid == 2 then return "INT8"
    elseif tid == 3 then return "INT16"
    elseif tid == 4 then return "INT32"
    elseif tid == 5 then return "INT64"
    elseif tid == 6 then return "UINT8"
    elseif tid == 7 then return "UINT16"
    elseif tid == 8 then return "UINT32"
    elseif tid == 9 then return "UINT64"
    elseif tid == 10 then return "FLOAT"
    elseif tid == 11 then return "DOUBLE"
    elseif tid == 12 then return "VARCHAR"
    elseif tid == 13 then return "DATE"
    elseif tid == 14 then return "TIMESTAMP"
    elseif tid == 15 then return "VECTOR_F32"
    else return "UNKNOWN"
    end
end

local terra make_type_fn(tid: int32, dim: uint32) : DataType
    var dt : DataType
    dt:init(tid, dim)
    return dt
end

types.make_type = make_type_fn
types.DataType = DataType
return types
