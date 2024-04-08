-- test_nested_queries.t
-- Test suite verifying SQL parser precedence, complex multi-clause expressions,
-- joins with aliases, and aggregate query structures.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local token = require("src.parser/token")
local ast = require("src.parser/ast")
local parser = require("src.parser/parser")

terra run_nested_query_tests() : int
    C.printf("=== Running Quarry Complex SQL AST and Nested Query Tests ===\n")

    var arena : alloc.Arena
    arena:init(65536)

    -- Test 1: Operator Precedence (* takes precedence over +)
    var sql1 = "SELECT 10 + 20 * 30;"
    var p1 : parser.Parser
    p1:init(sql1, &arena)
    var stmt1 = p1:parse()
    if stmt1 == nil or p1.has_error then
        C.printf("FAIL: query 1 parse failed: %s\n", &(p1.error_msg[0]))
        return 1
    end

    var root1 = stmt1.select_stmt.projections[0]
    if root1.expr_type ~= ast.EXPR_BINARY_OP or root1.op ~= token.TOKEN_PLUS then
        C.printf("FAIL: root operator expected '+'\n")
        return 1
    end
    if root1.right.expr_type ~= ast.EXPR_BINARY_OP or root1.right.op ~= token.TOKEN_STAR then
        C.printf("FAIL: right child operator expected '*'\n")
        return 1
    end
    C.printf("PASS: Test 1: Arithmetic precedence (* binds tighter than +)\n")

    -- Test 2: Logical Precedence (AND takes precedence over OR)
    var sql2 = "SELECT id FROM items WHERE a = 1 OR b = 2 AND c = 3;"
    var p2 : parser.Parser
    p2:init(sql2, &arena)
    var stmt2 = p2:parse()
    if stmt2 == nil or p2.has_error then
        C.printf("FAIL: query 2 parse failed: %s\n", &(p2.error_msg[0]))
        return 1
    end

    var where_expr = stmt2.select_stmt.where_clause
    if where_expr.expr_type ~= ast.EXPR_BINARY_OP or where_expr.op ~= token.TOKEN_OR then
        C.printf("FAIL: root WHERE operator expected 'OR'\n")
        return 1
    end
    if where_expr.right.expr_type ~= ast.EXPR_BINARY_OP or where_expr.right.op ~= token.TOKEN_AND then
        C.printf("FAIL: right WHERE operand expected 'AND'\n")
        return 1
    end
    C.printf("PASS: Test 2: Logical precedence (AND binds tighter than OR)\n")

    -- Test 3: Complex Multi-Aggregate with GROUP BY and ORDER BY
    var sql3 = "SELECT category, COUNT(*) AS cnt, SUM(amount) AS total, AVG(score) AS avg_score FROM transactions GROUP BY category ORDER BY total DESC LIMIT 20;"
    var p3 : parser.Parser
    p3:init(sql3, &arena)
    var stmt3 = p3:parse()
    if stmt3 == nil or p3.has_error then
        C.printf("FAIL: query 3 parse failed: %s\n", &(p3.error_msg[0]))
        return 1
    end

    var sel3 = &(stmt3.select_stmt)
    if sel3.num_projections ~= 4 then
        C.printf("FAIL: expected 4 projections, got %u\n", sel3.num_projections)
        return 1
    end
    if sel3.num_group_by ~= 1 or sel3.num_order_by ~= 1 or sel3.limit_val ~= 20 then
        C.printf("FAIL: group by, order by, or limit mismatch\n")
        return 1
    end
    C.printf("PASS: Test 3: Multi-aggregate GROUP BY with ORDER BY and LIMIT 20\n")

    -- Test 4: Equijoin with Aliases
    var sql4 = "SELECT o.order_id, c.name FROM orders o JOIN customers c ON o.customer_id = c.id WHERE o.total > 500;"
    var p4 : parser.Parser
    p4:init(sql4, &arena)
    var stmt4 = p4:parse()
    if stmt4 == nil or p4.has_error then
        C.printf("FAIL: query 4 parse failed: %s\n", &(p4.error_msg[0]))
        return 1
    end

    var sel4 = &(stmt4.select_stmt)
    if not sel4.has_join or C.strcmp(&(sel4.join_table[0]), "customers") ~= 0 then
        C.printf("FAIL: join table mismatch\n")
        return 1
    end
    if sel4.join_on == nil then
        C.printf("FAIL: join ON predicate expected non-nil expression\n")
        return 1
    end
    C.printf("PASS: Test 4: Relational JOIN with table alias qualification and ON condition\n")

    arena:destroy()
    C.printf("=== ALL NESTED QUERY AND PRECEDENCE TESTS PASSED (4/4) ===\n")
    return 0
end

local code = run_nested_query_tests()
if code ~= 0 then
    os.exit(1)
end
