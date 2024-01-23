local ffi = require("ffi")
-- Quarry AST expression to Terra quotation compiler
-- Recursively translates relational AST expressions into native Terra LLVM quotations.

local C = require("src.common.c").C
local ast = require("src.parser/ast")
local token = require("src.parser/token")
local builder = require("src.jit/builder")

local expr_compiler = {}

-- Compiles an ExprNode AST into a hygienic Terra quotation
function expr_compiler.compile(node, col_syms, col_name_to_idx)
    if node == nil then
        return `true
    end

    local etype = node.expr_type

    if etype == ast.EXPR_LITERAL then
        local tid = node.literal.type_id
        if tid == 1 then -- BOOL
            local b = node.literal.val_bool
            return `[b]
        elseif tid >= 2 and tid <= 9 then -- INT
            local v = node.literal:as_i64()
            return `[v]
        elseif tid == 10 or tid == 11 then -- FLOAT / DOUBLE
            local v = node.literal:as_f64()
            return `[v]
        else
            local v = node.literal:as_i64()
            return `[v]
        end

    elseif etype == ast.EXPR_COLUMN_REF then
        local cname = ffi.string(node.column_name)
        local idx = col_name_to_idx[cname]
        if idx and col_syms[idx] then
            local sym = col_syms[idx]
            return `[sym]
        else
            -- Default to first column symbol if unmapped
            local sym = col_syms[0] or symbol(int64, "unknown")
            return `[sym]
        end

    elseif etype == ast.EXPR_BINARY_OP then
        local left_q = expr_compiler.compile(node.left, col_syms, col_name_to_idx)
        local right_q = expr_compiler.compile(node.right, col_syms, col_name_to_idx)
        return builder.build_binary_quote(node.op, left_q, right_q)

    elseif etype == ast.EXPR_UNARY_OP then
        local sub_q = expr_compiler.compile(node.left, col_syms, col_name_to_idx)
        if node.op == token.TOKEN_NOT then
            return `(not [sub_q])
        elseif node.op == token.TOKEN_MINUS then
            return `(-[sub_q])
        else
            return `[sub_q]
        end

    else
        return `true
    end
end

return expr_compiler
