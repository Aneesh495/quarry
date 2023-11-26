-- Quarry status and error handling subsystem
-- Provides explicit error tracking with formatted message buffers.

local C = require("src.common.c").C

local status = {}

-- Status codes
status.OK = 0
status.SYNTAX_ERROR = 1
status.TYPE_ERROR = 2
status.TABLE_NOT_FOUND = 3
status.COLUMN_NOT_FOUND = 4
status.EXECUTION_ERROR = 5
status.OUT_OF_MEMORY = 6
status.IO_ERROR = 7
status.NOT_IMPLEMENTED = 8

struct Status {
    code: int32,
    message: int8[256]
}

terra Status:is_ok() : bool
    return self.code == 0
end

terra Status:is_err() : bool
    return self.code ~= 0
end

terra Status:get_code() : int32
    return self.code
end

terra Status:get_message() : &int8
    return &(self.message[0])
end

terra status.ok() : Status
    var s : Status
    s.code = 0
    s.message[0] = 0
    return s
end

terra status.err(code: int32, msg: &int8) : Status
    var s : Status
    s.code = code
    if msg ~= nil then
        C.strncpy(&(s.message[0]), msg, 255)
        s.message[255] = 0
    else
        s.message[0] = 0
    end
    return s
end

status.Status = Status
return status
