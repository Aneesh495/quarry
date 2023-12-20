-- Quarry SQL token subsystem
-- Defines keywords, operators, literals, and token structures for lexical analysis.

local C = require("src.common.c").C

local token = {}

-- Token types
token.TOKEN_EOF             = 0
token.TOKEN_ILLEGAL         = 1

-- Literals & Identifiers
token.TOKEN_IDENTIFIER      = 2
token.TOKEN_INT_LITERAL     = 3
token.TOKEN_FLOAT_LITERAL   = 4
token.TOKEN_STRING_LITERAL  = 5
token.TOKEN_VECTOR_LITERAL  = 6

-- Operators
token.TOKEN_PLUS            = 10
token.TOKEN_MINUS           = 11
token.TOKEN_STAR            = 12
token.TOKEN_SLASH           = 13
token.TOKEN_PERCENT         = 14
token.TOKEN_EQ              = 15
token.TOKEN_NEQ             = 16
token.TOKEN_LT              = 17
token.TOKEN_LTE             = 18
token.TOKEN_GT              = 19
token.TOKEN_GTE             = 20

-- Punctuation
token.TOKEN_COMMA           = 30
token.TOKEN_SEMICOLON       = 31
token.TOKEN_LPAREN          = 32
token.TOKEN_RPAREN          = 33
token.TOKEN_LBRACKET        = 34
token.TOKEN_RBRACKET        = 35
token.TOKEN_DOT             = 36

-- Keywords
token.TOKEN_SELECT          = 50
token.TOKEN_FROM            = 51
token.TOKEN_WHERE           = 52
token.TOKEN_JOIN            = 53
token.TOKEN_INNER           = 54
token.TOKEN_LEFT            = 55
token.TOKEN_RIGHT           = 56
token.TOKEN_ON              = 57
token.TOKEN_GROUP           = 58
token.TOKEN_BY              = 59
token.TOKEN_HAVING          = 60
token.TOKEN_ORDER           = 61
token.TOKEN_ASC             = 62
token.TOKEN_DESC            = 63
token.TOKEN_LIMIT           = 64
token.TOKEN_OFFSET          = 65
token.TOKEN_AS              = 66
token.TOKEN_AND             = 67
token.TOKEN_OR              = 68
token.TOKEN_NOT             = 69
token.TOKEN_IN              = 70
token.TOKEN_BETWEEN         = 71
token.TOKEN_LIKE            = 72
token.TOKEN_IS              = 73
token.TOKEN_NULL            = 74
token.TOKEN_TRUE            = 75
token.TOKEN_FALSE           = 76
token.TOKEN_CREATE          = 77
token.TOKEN_TABLE           = 78
token.TOKEN_INSERT          = 79
token.TOKEN_INTO            = 80
token.TOKEN_VALUES          = 81
token.TOKEN_COPY            = 82
token.TOKEN_EXPLAIN         = 83
token.TOKEN_JIT             = 84
token.TOKEN_ANALYZE         = 85
token.TOKEN_OVER            = 86
token.TOKEN_PARTITION       = 87
token.TOKEN_WINDOW          = 88
token.TOKEN_VECTOR_KNN      = 89

struct Token {
    token_type: int32,
    lexeme: int8[64],
    int_val: int64,
    float_val: double,
    line: uint32,
    col: uint32
}

terra Token:init()
    self.token_type = token.TOKEN_EOF
    self.lexeme[0] = 0
    self.int_val = 0
    self.float_val = 0.0
    self.line = 1
    self.col = 1
end

terra Token:is(expected: int32) : bool
    return self.token_type == expected
end

terra Token:name() : &int8
    var tt = self.token_type
    if tt == token.TOKEN_EOF then return "EOF"
    elseif tt == token.TOKEN_IDENTIFIER then return "IDENTIFIER"
    elseif tt == token.TOKEN_INT_LITERAL then return "INT_LITERAL"
    elseif tt == token.TOKEN_FLOAT_LITERAL then return "FLOAT_LITERAL"
    elseif tt == token.TOKEN_STRING_LITERAL then return "STRING_LITERAL"
    elseif tt == token.TOKEN_VECTOR_LITERAL then return "VECTOR_LITERAL"
    elseif tt == token.TOKEN_SELECT then return "SELECT"
    elseif tt == token.TOKEN_FROM then return "FROM"
    elseif tt == token.TOKEN_WHERE then return "WHERE"
    elseif tt == token.TOKEN_JOIN then return "JOIN"
    elseif tt == token.TOKEN_GROUP then return "GROUP"
    elseif tt == token.TOKEN_ORDER then return "ORDER"
    elseif tt == token.TOKEN_LIMIT then return "LIMIT"
    else return "TOKEN"
    end
end

token.Token = Token
return token
