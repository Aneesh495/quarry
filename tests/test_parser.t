-- Test suite for Quarry SQL parser and lexer

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local token = require("src.parser/token")
local lexer = require("src.parser/lexer")
local ast = require("src.parser/ast")
local parser = require("src.parser/parser")

terra run_parser_tests() : int
    C.printf("=== Running Quarry SQL Parser Tests ===\n")

    var arena : alloc.Arena
    arena:init(65536)

    -- Test 1: Lexer tokenization
    var sql_lex = "SELECT id, price * 1.05 AS total_price FROM orders WHERE status = 'COMPLETED' LIMIT 10;"
    var lex : lexer.Lexer
    lex:init(sql_lex)

    var t = lex:next_token()
    if t.token_type ~= token.TOKEN_SELECT then
        C.printf("FAIL: expected SELECT, got %s\n", t:name())
        return 1
    end
    t = lex:next_token()
    if t.token_type ~= token.TOKEN_IDENTIFIER or C.strcmp(&(t.lexeme[0]), "id") ~= 0 then
        C.printf("FAIL: expected identifier 'id'\n")
        return 1
    end
    C.printf("PASS: Lexer tokenization of keywords, identifiers, and literals\n")

    -- Test 2: Expression parsing with operator precedence (1 + 2 * 3 -> 1 + (2 * 3))
    var sql_expr = "SELECT 1 + 2 * 3"
    var p_expr : parser.Parser
    p_expr:init(sql_expr, &arena)
    var stmt_expr = p_expr:parse()
    if stmt_expr == nil or p_expr.has_error then
        C.printf("FAIL: parse_expression failed: %s\n", &(p_expr.error_msg[0]))
        return 1
    end
    var root_expr = stmt_expr.select_stmt.projections[0]
    if root_expr.expr_type ~= ast.EXPR_BINARY_OP or root_expr.op ~= token.TOKEN_PLUS then
        C.printf("FAIL: root operator expected '+'\n")
        return 1
    end
    if root_expr.right.expr_type ~= ast.EXPR_BINARY_OP or root_expr.right.op ~= token.TOKEN_STAR then
        C.printf("FAIL: right operand expected '*'\n")
        return 1
    end
    C.printf("PASS: Expression Pratt precedence (* binds tighter than +)\n")

    -- Test 3: Complex SELECT query parsing
    var complex_sql = "SELECT o.customer_id, COUNT(*) AS order_cnt, SUM(o.total) AS total_spent FROM orders o JOIN customers c ON o.customer_id = c.id WHERE o.status = 'ACTIVE' GROUP BY o.customer_id ORDER BY total_spent DESC LIMIT 5;"

    var p_complex : parser.Parser
    p_complex:init(complex_sql, &arena)
    var stmt_complex = p_complex:parse()
    if stmt_complex == nil or p_complex.has_error then
        C.printf("FAIL: complex SQL parsing failed: %s\n", &(p_complex.error_msg[0]))
        return 1
    end

    var sel = &(stmt_complex.select_stmt)
    if sel.num_projections ~= 3 then
        C.printf("FAIL: expected 3 projections, got %u\n", sel.num_projections)
        return 1
    end
    if C.strcmp(&(sel.from_table[0]), "orders") ~= 0 then
        C.printf("FAIL: expected from table 'orders', got '%s'\n", &(sel.from_table[0]))
        return 1
    end
    if not sel.has_join or C.strcmp(&(sel.join_table[0]), "customers") ~= 0 then
        C.printf("FAIL: join table expected 'customers'\n")
        return 1
    end
    if sel.where_clause == nil then
        C.printf("FAIL: where clause should not be nil\n")
        return 1
    end
    if sel.num_group_by ~= 1 or sel.num_order_by ~= 1 or sel.order_asc[0] ~= false then
        C.printf("FAIL: group by or order by mismatch\n")
        return 1
    end
    if sel.limit_val ~= 5 then
        C.printf("FAIL: limit expected 5, got %lld\n", sel.limit_val)
        return 1
    end
    C.printf("PASS: Multi-clause SELECT parsing (FROM, JOIN ON, WHERE, GROUP BY, ORDER BY DESC, LIMIT)\n")

    -- Test 4: CREATE TABLE with vector column
    var ddl_sql = "CREATE TABLE embeddings (doc_id INT, title VARCHAR, embedding VECTOR(384));"
    var p_ddl : parser.Parser
    p_ddl:init(ddl_sql, &arena)
    var stmt_ddl = p_ddl:parse()
    if stmt_ddl == nil or p_ddl.has_error then
        C.printf("FAIL: CREATE TABLE parsing failed: %s\n", &(p_ddl.error_msg[0]))
        return 1
    end
    var ct = &(stmt_ddl.create_stmt)
    if ct.num_columns ~= 3 then
        C.printf("FAIL: expected 3 columns in CREATE TABLE, got %u\n", ct.num_columns)
        return 1
    end
    if ct.column_types[2].type_id ~= 15 or ct.column_types[2].vector_dim ~= 384 then
        C.printf("FAIL: vector column type or dim mismatch (dim=%u)\n", ct.column_types[2].vector_dim)
        return 1
    end
    C.printf("PASS: CREATE TABLE DDL parsing with 384-dimensional VECTOR type\n")

    -- Test 5: EXPLAIN JIT parsing
    var explain_sql = "EXPLAIN JIT SELECT x, y FROM points WHERE x > 10;"
    var p_exp : parser.Parser
    p_exp:init(explain_sql, &arena)
    var stmt_exp = p_exp:parse()
    if stmt_exp == nil or not stmt_exp.select_stmt.is_explain or not stmt_exp.select_stmt.is_jit then
        C.printf("FAIL: EXPLAIN JIT flag check failed\n")
        return 1
    end
    C.printf("PASS: EXPLAIN JIT command recognition\n")

    arena:destroy()
    C.printf("=== ALL PARSER TESTS PASSED (5/5) ===\n")
    return 0
end

local code = run_parser_tests()
if code ~= 0 then
    os.exit(1)
end
