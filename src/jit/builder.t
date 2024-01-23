-- Quarry JIT quotation builder and hygienic symbol subsystem
-- Synthesizes typed Terra symbols and quotations for holistic query compilation.

local token = require("src.parser/token")
local types = require("src.types.type")

local builder = {}

-- Allocates an array of Terra symbols for columnar loop variables
function builder.create_column_symbols(num_cols, col_types)
    local syms = {}
    for i = 0, num_cols - 1 do
        local t = int64
        if col_types and col_types[i] then
            local tid = col_types[i].type_id
            if tid == types.DOUBLE or tid == types.FLOAT then
                t = double
            elseif tid == types.BOOL then
                t = bool
            else
                t = int64
            end
        end
        syms[i] = symbol(t, "col_" .. tostring(i))
    end
    return syms
end

-- Constructs a binary operation quote between two Terra expressions
function builder.build_binary_quote(op, left_q, right_q)
    if op == token.TOKEN_PLUS then
        return `([left_q] + [right_q])
    elseif op == token.TOKEN_MINUS then
        return `([left_q] - [right_q])
    elseif op == token.TOKEN_STAR then
        return `([left_q] * [right_q])
    elseif op == token.TOKEN_SLASH then
        return `([left_q] / [right_q])
    elseif op == token.TOKEN_PERCENT then
        return `([left_q] % [right_q])
    elseif op == token.TOKEN_EQ then
        return `([left_q] == [right_q])
    elseif op == token.TOKEN_NEQ then
        return `([left_q] ~= [right_q])
    elseif op == token.TOKEN_LT then
        return `([left_q] < [right_q])
    elseif op == token.TOKEN_LTE then
        return `([left_q] <= [right_q])
    elseif op == token.TOKEN_GT then
        return `([left_q] > [right_q])
    elseif op == token.TOKEN_GTE then
        return `([left_q] >= [right_q])
    elseif op == token.TOKEN_AND then
        return `([left_q] and [right_q])
    elseif op == token.TOKEN_OR then
        return `([left_q] or [right_q])
    else
        return `([left_q] == [right_q])
    end
end

return builder
