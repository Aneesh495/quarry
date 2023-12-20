-- Quarry SQL lexical analyzer
-- High-throughput deterministic scanner with zero allocations for identifier tokens.

local C = require("src.common.c").C
local token = require("src.parser/token")

local Token = token.Token
local lexer = {}

struct Lexer {
    src: &int8,
    len: uint32,
    pos: uint32,
    line: uint32,
    col: uint32
}

terra Lexer:init(sql: &int8)
    self.src = sql
    if sql ~= nil then
        self.len = [uint32](C.strlen(sql))
    else
        self.len = 0
    end
    self.pos = 0
    self.line = 1
    self.col = 1
end

terra Lexer:peek() : int8
    if self.pos >= self.len then return 0 end
    return self.src[self.pos]
end

terra Lexer:advance() : int8
    if self.pos >= self.len then return 0 end
    var ch = self.src[self.pos]
    self.pos = self.pos + 1
    if ch == 10 then -- newline '\n'
        self.line = self.line + 1
        self.col = 1
    else
        self.col = self.col + 1
    end
    return ch
end

terra Lexer:skip_whitespace_and_comments()
    while self.pos < self.len do
        var ch = self:peek()
        if ch == 32 or ch == 9 or ch == 10 or ch == 13 then -- ' ', '\t', '\n', '\r'
            self:advance()
        elseif ch == 45 and self.pos + 1 < self.len and self.src[self.pos + 1] == 45 then -- '--' comment
            self:advance(); self:advance()
            while self.pos < self.len and self:peek() ~= 10 do
                self:advance()
            end
        else
            break
        end
    end
end

-- Case-insensitive string match
terra Lexer:match_keyword(s: &int8, kw: &int8) : bool
    var i : uint32 = 0
    while s[i] ~= 0 and kw[i] ~= 0 do
        var c1 = s[i]
        var c2 = kw[i]
        if c1 >= 97 and c1 <= 122 then c1 = c1 - 32 end -- toupper
        if c2 >= 97 and c2 <= 122 then c2 = c2 - 32 end
        if c1 ~= c2 then return false end
        i = i + 1
    end
    return s[i] == 0 and kw[i] == 0
end

terra Lexer:classify_identifier(lexeme: &int8) : int32
    if self:match_keyword(lexeme, "SELECT") then return token.TOKEN_SELECT
    elseif self:match_keyword(lexeme, "FROM") then return token.TOKEN_FROM
    elseif self:match_keyword(lexeme, "WHERE") then return token.TOKEN_WHERE
    elseif self:match_keyword(lexeme, "JOIN") then return token.TOKEN_JOIN
    elseif self:match_keyword(lexeme, "INNER") then return token.TOKEN_INNER
    elseif self:match_keyword(lexeme, "LEFT") then return token.TOKEN_LEFT
    elseif self:match_keyword(lexeme, "RIGHT") then return token.TOKEN_RIGHT
    elseif self:match_keyword(lexeme, "ON") then return token.TOKEN_ON
    elseif self:match_keyword(lexeme, "GROUP") then return token.TOKEN_GROUP
    elseif self:match_keyword(lexeme, "BY") then return token.TOKEN_BY
    elseif self:match_keyword(lexeme, "HAVING") then return token.TOKEN_HAVING
    elseif self:match_keyword(lexeme, "ORDER") then return token.TOKEN_ORDER
    elseif self:match_keyword(lexeme, "ASC") then return token.TOKEN_ASC
    elseif self:match_keyword(lexeme, "DESC") then return token.TOKEN_DESC
    elseif self:match_keyword(lexeme, "LIMIT") then return token.TOKEN_LIMIT
    elseif self:match_keyword(lexeme, "OFFSET") then return token.TOKEN_OFFSET
    elseif self:match_keyword(lexeme, "AS") then return token.TOKEN_AS
    elseif self:match_keyword(lexeme, "AND") then return token.TOKEN_AND
    elseif self:match_keyword(lexeme, "OR") then return token.TOKEN_OR
    elseif self:match_keyword(lexeme, "NOT") then return token.TOKEN_NOT
    elseif self:match_keyword(lexeme, "IN") then return token.TOKEN_IN
    elseif self:match_keyword(lexeme, "BETWEEN") then return token.TOKEN_BETWEEN
    elseif self:match_keyword(lexeme, "LIKE") then return token.TOKEN_LIKE
    elseif self:match_keyword(lexeme, "IS") then return token.TOKEN_IS
    elseif self:match_keyword(lexeme, "NULL") then return token.TOKEN_NULL
    elseif self:match_keyword(lexeme, "TRUE") then return token.TOKEN_TRUE
    elseif self:match_keyword(lexeme, "FALSE") then return token.TOKEN_FALSE
    elseif self:match_keyword(lexeme, "CREATE") then return token.TOKEN_CREATE
    elseif self:match_keyword(lexeme, "TABLE") then return token.TOKEN_TABLE
    elseif self:match_keyword(lexeme, "INSERT") then return token.TOKEN_INSERT
    elseif self:match_keyword(lexeme, "INTO") then return token.TOKEN_INTO
    elseif self:match_keyword(lexeme, "VALUES") then return token.TOKEN_VALUES
    elseif self:match_keyword(lexeme, "COPY") then return token.TOKEN_COPY
    elseif self:match_keyword(lexeme, "EXPLAIN") then return token.TOKEN_EXPLAIN
    elseif self:match_keyword(lexeme, "JIT") then return token.TOKEN_JIT
    elseif self:match_keyword(lexeme, "ANALYZE") then return token.TOKEN_ANALYZE
    elseif self:match_keyword(lexeme, "OVER") then return token.TOKEN_OVER
    elseif self:match_keyword(lexeme, "PARTITION") then return token.TOKEN_PARTITION
    elseif self:match_keyword(lexeme, "WINDOW") then return token.TOKEN_WINDOW
    elseif self:match_keyword(lexeme, "VECTOR_KNN") then return token.TOKEN_VECTOR_KNN
    else return token.TOKEN_IDENTIFIER
    end
end

terra Lexer:next_token() : Token
    self:skip_whitespace_and_comments()

    var tok : Token
    tok:init()
    tok.line = self.line
    tok.col = self.col

    if self.pos >= self.len then
        tok.token_type = token.TOKEN_EOF
        return tok
    end

    var ch = self:peek()

    -- Single character operators and punctuation
    if ch == 43 then -- '+'
        self:advance()
        tok.token_type = token.TOKEN_PLUS
        tok.lexeme[0] = 43; tok.lexeme[1] = 0
        return tok
    elseif ch == 45 then -- '-'
        self:advance()
        tok.token_type = token.TOKEN_MINUS
        tok.lexeme[0] = 45; tok.lexeme[1] = 0
        return tok
    elseif ch == 42 then -- '*'
        self:advance()
        tok.token_type = token.TOKEN_STAR
        tok.lexeme[0] = 42; tok.lexeme[1] = 0
        return tok
    elseif ch == 47 then -- '/'
        self:advance()
        tok.token_type = token.TOKEN_SLASH
        tok.lexeme[0] = 47; tok.lexeme[1] = 0
        return tok
    elseif ch == 37 then -- '%'
        self:advance()
        tok.token_type = token.TOKEN_PERCENT
        tok.lexeme[0] = 37; tok.lexeme[1] = 0
        return tok
    elseif ch == 44 then -- ','
        self:advance()
        tok.token_type = token.TOKEN_COMMA
        tok.lexeme[0] = 44; tok.lexeme[1] = 0
        return tok
    elseif ch == 59 then -- ';'
        self:advance()
        tok.token_type = token.TOKEN_SEMICOLON
        tok.lexeme[0] = 59; tok.lexeme[1] = 0
        return tok
    elseif ch == 40 then -- '('
        self:advance()
        tok.token_type = token.TOKEN_LPAREN
        tok.lexeme[0] = 40; tok.lexeme[1] = 0
        return tok
    elseif ch == 41 then -- ')'
        self:advance()
        tok.token_type = token.TOKEN_RPAREN
        tok.lexeme[0] = 41; tok.lexeme[1] = 0
        return tok
    elseif ch == 91 then -- '['
        self:advance()
        tok.token_type = token.TOKEN_LBRACKET
        tok.lexeme[0] = 91; tok.lexeme[1] = 0
        return tok
    elseif ch == 93 then -- ']'
        self:advance()
        tok.token_type = token.TOKEN_RBRACKET
        tok.lexeme[0] = 93; tok.lexeme[1] = 0
        return tok
    elseif ch == 46 then -- '.'
        self:advance()
        tok.token_type = token.TOKEN_DOT
        tok.lexeme[0] = 46; tok.lexeme[1] = 0
        return tok
    elseif ch == 61 then -- '='
        self:advance()
        tok.token_type = token.TOKEN_EQ
        tok.lexeme[0] = 61; tok.lexeme[1] = 0
        return tok
    elseif ch == 60 then -- '<' or '<=' or '<>'
        self:advance()
        if self:peek() == 61 then -- '<='
            self:advance()
            tok.token_type = token.TOKEN_LTE
            tok.lexeme[0] = 60; tok.lexeme[1] = 61; tok.lexeme[2] = 0
        elseif self:peek() == 62 then -- '<>'
            self:advance()
            tok.token_type = token.TOKEN_NEQ
            tok.lexeme[0] = 60; tok.lexeme[1] = 62; tok.lexeme[2] = 0
        else
            tok.token_type = token.TOKEN_LT
            tok.lexeme[0] = 60; tok.lexeme[1] = 0
        end
        return tok
    elseif ch == 62 then -- '>' or '>='
        self:advance()
        if self:peek() == 61 then -- '>='
            self:advance()
            tok.token_type = token.TOKEN_GTE
            tok.lexeme[0] = 62; tok.lexeme[1] = 61; tok.lexeme[2] = 0
        else
            tok.token_type = token.TOKEN_GT
            tok.lexeme[0] = 62; tok.lexeme[1] = 0
        end
        return tok
    elseif ch == 33 and self.pos + 1 < self.len and self.src[self.pos + 1] == 61 then -- '!='
        self:advance(); self:advance()
        tok.token_type = token.TOKEN_NEQ
        tok.lexeme[0] = 33; tok.lexeme[1] = 61; tok.lexeme[2] = 0
        return tok
    end

    -- String literals: 'example'
    if ch == 39 then -- '\''
        self:advance()
        var idx : uint32 = 0
        while self.pos < self.len and self:peek() ~= 39 and idx < 63 do
            tok.lexeme[idx] = self:advance()
            idx = idx + 1
        end
        tok.lexeme[idx] = 0
        if self:peek() == 39 then self:advance() end -- consume closing quote
        tok.token_type = token.TOKEN_STRING_LITERAL
        return tok
    end

    -- Numeric literals (integers and floats)
    if (ch >= 48 and ch <= 57) or (ch == 46 and self.pos + 1 < self.len and self.src[self.pos + 1] >= 48 and self.src[self.pos + 1] <= 57) then
        var idx : uint32 = 0
        var is_float = false
        while self.pos < self.len and idx < 63 do
            var c = self:peek()
            if c >= 48 and c <= 57 then
                tok.lexeme[idx] = self:advance()
                idx = idx + 1
            elseif c == 46 and not is_float then
                is_float = true
                tok.lexeme[idx] = self:advance()
                idx = idx + 1
            else
                break
            end
        end
        tok.lexeme[idx] = 0

        if is_float then
            tok.token_type = token.TOKEN_FLOAT_LITERAL
            tok.float_val = C.strtod(&(tok.lexeme[0]), nil)
        else
            tok.token_type = token.TOKEN_INT_LITERAL
            tok.int_val = C.strtoll(&(tok.lexeme[0]), nil, 10)
        end
        return tok
    end

    -- Identifiers and keywords (letters, underscore)
    if (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 95 then
        var idx : uint32 = 0
        while self.pos < self.len and idx < 63 do
            var c = self:peek()
            if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 then
                tok.lexeme[idx] = self:advance()
                idx = idx + 1
            else
                break
            end
        end
        tok.lexeme[idx] = 0
        tok.token_type = self:classify_identifier(&(tok.lexeme[0]))
        return tok
    end

    -- Unknown token character
    tok.token_type = token.TOKEN_ILLEGAL
    tok.lexeme[0] = self:advance()
    tok.lexeme[1] = 0
    return tok
end

lexer.Lexer = Lexer
return lexer
