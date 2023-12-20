-- Quarry recursive descent SQL parser with Pratt expression precedence
-- Transforms SQL token streams into structured AST statements.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local value = require("src.types.value")
local token = require("src.parser/token")
local lexer = require("src.parser/lexer")
local ast = require("src.parser/ast")

local Token = token.Token
local Lexer = lexer.Lexer
local ExprNode = ast.ExprNode
local Statement = ast.Statement

local parser = {}

struct Parser {
    lex: Lexer,
    curr: Token,
    prev: Token,
    arena: &alloc.Arena,
    has_error: bool,
    error_msg: int8[256]
}

terra Parser:init(sql: &int8, arena: &alloc.Arena)
    self.lex:init(sql)
    self.arena = arena
    self.has_error = false
    self.error_msg[0] = 0
    self.curr = self.lex:next_token()
    self.prev:init()
end

terra Parser:advance() : Token
    self.prev = self.curr
    self.curr = self.lex:next_token()
    return self.prev
end

terra Parser:check(token_type: int32) : bool
    return self.curr.token_type == token_type
end

terra Parser:match_token(token_type: int32) : bool
    if self:check(token_type) then
        self:advance()
        return true
    end
    return false
end

terra Parser:set_error(msg: &int8)
    self.has_error = true
    C.strncpy(&(self.error_msg[0]), msg, 255)
    self.error_msg[255] = 0
end

-- Expression parsing precedence table
local PRECEDENCE_NONE       = 0
local PRECEDENCE_OR         = 1
local PRECEDENCE_AND        = 2
local PRECEDENCE_COMPARE    = 3 -- =, <>, <, <=, >, >=
local PRECEDENCE_TERM       = 4 -- +, -
local PRECEDENCE_FACTOR     = 5 -- *, /, %
local PRECEDENCE_UNARY      = 6 -- NOT, -
local PRECEDENCE_CALL       = 7 -- func()

terra Parser:get_precedence(token_type: int32) : int32
    if token_type == token.TOKEN_OR then return PRECEDENCE_OR
    elseif token_type == token.TOKEN_AND then return PRECEDENCE_AND
    elseif token_type >= token.TOKEN_EQ and token_type <= token.TOKEN_GTE then return PRECEDENCE_COMPARE
    elseif token_type == token.TOKEN_PLUS or token_type == token.TOKEN_MINUS then return PRECEDENCE_TERM
    elseif token_type >= token.TOKEN_STAR and token_type <= token.TOKEN_PERCENT then return PRECEDENCE_FACTOR
    else return PRECEDENCE_NONE
    end
end

-- Forward declaration for recursive expressions
terra Parser:parse_expression(min_prec: int32) : &ExprNode
    -- 1. Parse prefix / primary expression
    var left : &ExprNode = nil

    if self:match_token(token.TOKEN_INT_LITERAL) then
        var v = value.make_i64(self.prev.int_val)
        left = ast.new_literal(self.arena, &v)
    elseif self:match_token(token.TOKEN_FLOAT_LITERAL) then
        var v = value.make_f64(self.prev.float_val)
        left = ast.new_literal(self.arena, &v)
    elseif self:match_token(token.TOKEN_STRING_LITERAL) then
        var v = value.make_string(&(self.prev.lexeme[0]))
        left = ast.new_literal(self.arena, &v)
    elseif self:match_token(token.TOKEN_TRUE) then
        var v = value.make_bool(true)
        left = ast.new_literal(self.arena, &v)
    elseif self:match_token(token.TOKEN_FALSE) then
        var v = value.make_bool(false)
        left = ast.new_literal(self.arena, &v)
    elseif self:match_token(token.TOKEN_NULL) then
        var v = value.make_null(types.INT64)
        left = ast.new_literal(self.arena, &v)
    elseif self:match_token(token.TOKEN_MINUS) then
        var sub = self:parse_expression(PRECEDENCE_UNARY)
        left = ast.new_expr(self.arena, ast.EXPR_UNARY_OP)
        left.op = token.TOKEN_MINUS
        left.left = sub
    elseif self:match_token(token.TOKEN_NOT) then
        var sub = self:parse_expression(PRECEDENCE_UNARY)
        left = ast.new_expr(self.arena, ast.EXPR_UNARY_OP)
        left.op = token.TOKEN_NOT
        left.left = sub
    elseif self:match_token(token.TOKEN_LPAREN) then
        left = self:parse_expression(PRECEDENCE_NONE)
        if not self:match_token(token.TOKEN_RPAREN) then
            self:set_error("Expected ')' after parenthesized expression")
            return nil
        end
    elseif self:match_token(token.TOKEN_IDENTIFIER) then
        var id_name : int8[64]
        C.strncpy(&(id_name[0]), &(self.prev.lexeme[0]), 63)

        -- Check if it is a function call: identifier '('
        if self:match_token(token.TOKEN_LPAREN) then
            var args : (&ExprNode)[8]
            var arg_count : uint32 = 0

            if not self:check(token.TOKEN_RPAREN) then
                if self:match_token(token.TOKEN_STAR) then
                    -- COUNT(*) special case
                    var star_expr = ast.new_col_ref(self.arena, nil, "*")
                    args[0] = star_expr
                    arg_count = 1
                else
                    args[arg_count] = self:parse_expression(PRECEDENCE_NONE)
                    arg_count = arg_count + 1
                    while self:match_token(token.TOKEN_COMMA) and arg_count < 8 do
                        args[arg_count] = self:parse_expression(PRECEDENCE_NONE)
                        arg_count = arg_count + 1
                    end
                end
            end

            if not self:match_token(token.TOKEN_RPAREN) then
                self:set_error("Expected ')' after function arguments")
                return nil
            end

            left = ast.new_func_call(self.arena, &(id_name[0]), arg_count, &(args[0]))
        elseif self:match_token(token.TOKEN_DOT) then
            -- table.column
            if not self:match_token(token.TOKEN_IDENTIFIER) then
                self:set_error("Expected column identifier after '.'")
                return nil
            end
            left = ast.new_col_ref(self.arena, &(id_name[0]), &(self.prev.lexeme[0]))
        else
            -- bare column
            left = ast.new_col_ref(self.arena, nil, &(id_name[0]))
        end
    elseif self:match_token(token.TOKEN_STAR) then
        left = ast.new_col_ref(self.arena, nil, "*")
    else
        self:set_error("Unexpected token in expression")
        return nil
    end

    -- 2. Parse infix binary operations with Pratt precedence climbing
    while true do
        var prec = self:get_precedence(self.curr.token_type)
        if prec <= min_prec then
            break
        end

        var op_token = self:advance()
        var right = self:parse_expression(prec)
        if right == nil then return nil end

        var bin_node = ast.new_binary_op(self.arena, op_token.token_type, left, right)
        left = bin_node
    end

    return left
end

-- Parse full SELECT query
terra Parser:parse_select() : &Statement
    var stmt = [&Statement](self.arena:allocate(sizeof(Statement), 8))
    C.memset(stmt, 0, sizeof(Statement))
    stmt.stmt_type = ast.STMT_SELECT
    var sel = &(stmt.select_stmt)
    sel.limit_val = -1
    sel.offset_val = 0

    -- Parse projections (comma-separated list of expressions)
    var proj_count : uint32 = 0
    while true do
        var expr = self:parse_expression(PRECEDENCE_NONE)
        if expr == nil then return nil end

        sel.projections[proj_count] = expr

        -- Check for optional alias: "AS alias" or bare "alias"
        if self:match_token(token.TOKEN_AS) then
            if self:match_token(token.TOKEN_IDENTIFIER) then
                C.strncpy(&(sel.aliases[proj_count][0]), &(self.prev.lexeme[0]), 63)
            end
        elseif self:check(token.TOKEN_IDENTIFIER) and not self:check(token.TOKEN_FROM) then
            self:advance()
            C.strncpy(&(sel.aliases[proj_count][0]), &(self.prev.lexeme[0]), 63)
        else
            sel.aliases[proj_count][0] = 0
        end

        proj_count = proj_count + 1

        if not self:match_token(token.TOKEN_COMMA) then
            break
        end
    end
    sel.num_projections = proj_count

    -- Parse FROM clause
    if self:match_token(token.TOKEN_FROM) then
        if not self:match_token(token.TOKEN_IDENTIFIER) then
            self:set_error("Expected table name after FROM")
            return nil
        end
        C.strncpy(&(sel.from_table[0]), &(self.prev.lexeme[0]), 63)

        -- Optional table alias
        if self:check(token.TOKEN_IDENTIFIER) and not self:check(token.TOKEN_WHERE) and
           not self:check(token.TOKEN_JOIN) and not self:check(token.TOKEN_GROUP) and
           not self:check(token.TOKEN_ORDER) and not self:check(token.TOKEN_LIMIT) then
            self:advance()
            C.strncpy(&(sel.from_alias[0]), &(self.prev.lexeme[0]), 63)
        end
    end

    -- Parse optional JOIN clause: [INNER|LEFT] JOIN table ON condition
    if self:match_token(token.TOKEN_JOIN) or self:match_token(token.TOKEN_INNER) or self:match_token(token.TOKEN_LEFT) then
        sel.has_join = true
        if self.prev.token_type == token.TOKEN_LEFT then
            sel.join_type = ast.JOIN_LEFT
            self:match_token(token.TOKEN_JOIN)
        else
            sel.join_type = ast.JOIN_INNER
            if self.prev.token_type == token.TOKEN_INNER then
                self:match_token(token.TOKEN_JOIN)
            end
        end

        if not self:match_token(token.TOKEN_IDENTIFIER) then
            self:set_error("Expected table name in JOIN clause")
            return nil
        end
        C.strncpy(&(sel.join_table[0]), &(self.prev.lexeme[0]), 63)

        if not self:match_token(token.TOKEN_ON) then
            self:set_error("Expected ON condition in JOIN clause")
            return nil
        end
        sel.join_on = self:parse_expression(PRECEDENCE_NONE)
    end

    -- Parse optional WHERE clause
    if self:match_token(token.TOKEN_WHERE) then
        sel.where_clause = self:parse_expression(PRECEDENCE_NONE)
    end

    -- Parse optional GROUP BY clause
    if self:match_token(token.TOKEN_GROUP) then
        if not self:match_token(token.TOKEN_BY) then
            self:set_error("Expected BY after GROUP")
            return nil
        end
        var gb_count : uint32 = 0
        while true do
            var g_expr = self:parse_expression(PRECEDENCE_NONE)
            sel.group_by[gb_count] = g_expr
            gb_count = gb_count + 1
            if not self:match_token(token.TOKEN_COMMA) then break end
        end
        sel.num_group_by = gb_count
    end

    -- Parse optional HAVING clause
    if self:match_token(token.TOKEN_HAVING) then
        sel.having_clause = self:parse_expression(PRECEDENCE_NONE)
    end

    -- Parse optional ORDER BY clause
    if self:match_token(token.TOKEN_ORDER) then
        if not self:match_token(token.TOKEN_BY) then
            self:set_error("Expected BY after ORDER")
            return nil
        end
        var ob_count : uint32 = 0
        while true do
            var o_expr = self:parse_expression(PRECEDENCE_NONE)
            sel.order_by[ob_count] = o_expr
            sel.order_asc[ob_count] = true -- default ascending
            if self:match_token(token.TOKEN_DESC) then
                sel.order_asc[ob_count] = false
            else
                self:match_token(token.TOKEN_ASC)
            end
            ob_count = ob_count + 1
            if not self:match_token(token.TOKEN_COMMA) then break end
        end
        sel.num_order_by = ob_count
    end

    -- Parse optional LIMIT and OFFSET
    if self:match_token(token.TOKEN_LIMIT) then
        if self:match_token(token.TOKEN_INT_LITERAL) then
            sel.limit_val = self.prev.int_val
        end
        if self:match_token(token.TOKEN_OFFSET) then
            if self:match_token(token.TOKEN_INT_LITERAL) then
                sel.offset_val = self.prev.int_val
            end
        end
    end

    return stmt
end

-- Parse CREATE TABLE statement: CREATE TABLE name (col1 TYPE, col2 TYPE, ...)
terra Parser:parse_create_table() : &Statement
    var stmt = [&Statement](self.arena:allocate(sizeof(Statement), 8))
    C.memset(stmt, 0, sizeof(Statement))
    stmt.stmt_type = ast.STMT_CREATE_TABLE
    var ct = &(stmt.create_stmt)

    if not self:match_token(token.TOKEN_TABLE) then
        self:set_error("Expected TABLE after CREATE")
        return nil
    end

    if not self:match_token(token.TOKEN_IDENTIFIER) then
        self:set_error("Expected table name in CREATE TABLE")
        return nil
    end
    C.strncpy(&(ct.table_name[0]), &(self.prev.lexeme[0]), 63)

    if not self:match_token(token.TOKEN_LPAREN) then
        self:set_error("Expected '(' in column definitions")
        return nil
    end

    var col_count : uint32 = 0
    while not self:check(token.TOKEN_RPAREN) and self.curr.token_type ~= token.TOKEN_EOF do
        if not self:match_token(token.TOKEN_IDENTIFIER) then
            self:set_error("Expected column name")
            return nil
        end
        C.strncpy(&(ct.column_names[col_count][0]), &(self.prev.lexeme[0]), 63)

        -- Parse Type
        if not self:match_token(token.TOKEN_IDENTIFIER) then
            self:set_error("Expected column data type")
            return nil
        end

        var tname = &(self.prev.lexeme[0])
        var dt : types.DataType
        if self.lex:match_keyword(tname, "INT") or self.lex:match_keyword(tname, "INTEGER") or self.lex:match_keyword(tname, "BIGINT") then
            dt:init(types.INT64, 0)
        elseif self.lex:match_keyword(tname, "INT32") then
            dt:init(types.INT32, 0)
        elseif self.lex:match_keyword(tname, "DOUBLE") or self.lex:match_keyword(tname, "FLOAT8") or self.lex:match_keyword(tname, "DECIMAL") then
            dt:init(types.DOUBLE, 0)
        elseif self.lex:match_keyword(tname, "FLOAT") or self.lex:match_keyword(tname, "REAL") then
            dt:init(types.FLOAT, 0)
        elseif self.lex:match_keyword(tname, "VARCHAR") or self.lex:match_keyword(tname, "TEXT") or self.lex:match_keyword(tname, "STRING") then
            dt:init(types.VARCHAR, 0)
            -- Optional VARCHAR(N) length
            if self:match_token(token.TOKEN_LPAREN) then
                self:match_token(token.TOKEN_INT_LITERAL)
                self:match_token(token.TOKEN_RPAREN)
            end
        elseif self.lex:match_keyword(tname, "VECTOR") then
            -- VECTOR(dim)
            var dim : uint32 = 128 -- default dim
            if self:match_token(token.TOKEN_LPAREN) then
                if self:match_token(token.TOKEN_INT_LITERAL) then
                    dim = [uint32](self.prev.int_val)
                end
                self:match_token(token.TOKEN_RPAREN)
            end
            dt:init(types.VECTOR_F32, dim)
        else
            dt:init(types.INT64, 0)
        end

        ct.column_types[col_count] = dt
        col_count = col_count + 1

        if not self:match_token(token.TOKEN_COMMA) then
            break
        end
    end

    if not self:match_token(token.TOKEN_RPAREN) then
        self:set_error("Expected ')' after column definitions")
        return nil
    end

    ct.num_columns = col_count
    return stmt
end

-- Top-level statement dispatcher
terra Parser:parse() : &Statement
    if self:match_token(token.TOKEN_EXPLAIN) then
        var is_jit = false
        if self:match_token(token.TOKEN_JIT) then
            is_jit = true
        end
        if not self:match_token(token.TOKEN_SELECT) then
            self:set_error("Expected SELECT after EXPLAIN")
            return nil
        end
        var stmt = self:parse_select()
        if stmt ~= nil then
            stmt.select_stmt.is_explain = true
            stmt.select_stmt.is_jit = is_jit
        end
        return stmt
    elseif self:match_token(token.TOKEN_SELECT) then
        return self:parse_select()
    elseif self:match_token(token.TOKEN_CREATE) then
        return self:parse_create_table()
    else
        self:set_error("Unsupported SQL statement or syntax error")
        return nil
    end
end

parser.Parser = Parser
return parser
