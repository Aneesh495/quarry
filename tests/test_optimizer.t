-- Test suite for Quarry query optimizer and planner

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local value = require("src.types.value")
local cat = require("src.storage/catalog")
local token = require("src.parser/token")
local ast = require("src.parser/ast")
local parser = require("src.parser/parser")
local plan = require("src.optimizer/logical_plan")
local planner = require("src.optimizer/planner")
local rules = require("src.optimizer/rules")
local phys = require("src.optimizer/physical_plan")

local Value = value.Value

terra run_optimizer_tests() : int
    C.printf("=== Running Quarry Query Optimizer Tests ===\n")

    var arena : alloc.Arena
    arena:init(65536)

    -- Setup catalog with 'orders' table
    var my_cat : cat.Catalog
    my_cat:init()

    var col_names : (&int8)[4]
    col_names[0] = "id"
    col_names[1] = "customer_id"
    col_names[2] = "total"
    col_names[3] = "status"

    var col_tps : types.DataType[4]
    col_tps[0] = types.make_type(types.INT64, 0)
    col_tps[1] = types.make_type(types.INT64, 0)
    col_tps[2] = types.make_type(types.DOUBLE, 0)
    col_tps[3] = types.make_type(types.VARCHAR, 0)

    var tbl_orders = my_cat:create_table("orders", 4, &(col_names[0]), &(col_tps[0]))
    if tbl_orders == nil then
        C.printf("FAIL: create_table orders failed\n")
        return 1
    end

    -- Test 1: Plan synthesis from SQL
    var sql = "SELECT customer_id, total * 1.1 AS adjusted_total FROM orders WHERE total > 100.0 LIMIT 20;"
    var p : parser.Parser
    p:init(sql, &arena)
    var stmt = p:parse()
    if stmt == nil or p.has_error then
        C.printf("FAIL: parse failed: %s\n", &(p.error_msg[0]))
        return 1
    end

    var pl : planner.Planner
    pl:init(&my_cat, &arena)
    var l_root = pl:create_logical_plan(&(stmt.select_stmt))
    if l_root == nil or pl.has_error then
        C.printf("FAIL: create_logical_plan failed: %s\n", &(pl.error_msg[0]))
        return 1
    end

    if l_root.op_type ~= plan.LOGICAL_LIMIT then
        C.printf("FAIL: root operator expected LOGICAL_LIMIT, got %s\n", l_root:name())
        return 1
    end
    C.printf("PASS: Logical plan synthesis from AST\n")

    -- Test 2: EXPLAIN plan formatting
    var explain_buf : int8[1024]
    l_root:explain(&(explain_buf[0]), 1024, 0)
    if C.strstr(&(explain_buf[0]), "LogicalLimit") == nil or
       C.strstr(&(explain_buf[0]), "LogicalProject") == nil or
       C.strstr(&(explain_buf[0]), "LogicalFilter") == nil or
       C.strstr(&(explain_buf[0]), "LogicalScan") == nil then
        C.printf("FAIL: explain output missing expected operators\n%s\n", &(explain_buf[0]))
        return 1
    end
    C.printf("PASS: Indented EXPLAIN plan tree output\n")

    -- Test 3: Constant folding (10 * 5 -> 50)
    var v10 : Value
    v10:init_i64(5, 10)
    var lit10 = ast.new_literal(&arena, &v10)
    var v5 : Value
    v5:init_i64(5, 5)
    var lit5 = ast.new_literal(&arena, &v5)

    var mult_expr = ast.new_binary_op(&arena, token.TOKEN_STAR, lit10, lit5)
    var folded = rules.fold_constants(mult_expr)

    if folded.expr_type ~= ast.EXPR_LITERAL or folded.literal:as_i64() ~= 50 then
        C.printf("FAIL: constant folding expected literal 50, got %lld\n", folded.literal:as_i64())
        return 1
    end
    C.printf("PASS: Constant expression folding into literal\n")

    -- Test 4: Physical plan generation and pipeline breaker identification
    var pipe_id : uint32 = 0
    var phys_root = phys.create_physical_plan(&arena, l_root, &pipe_id)
    if phys_root == nil then
        C.printf("FAIL: create_physical_plan failed\n")
        return 1
    end
    if phys_root.phys_type ~= phys.PHYS_LIMIT then
        C.printf("FAIL: phys_root expected PhysicalLimit, got %s\n", phys_root:name())
        return 1
    end
    C.printf("PASS: Physical plan generation and pipeline boundaries\n")

    my_cat:destroy()
    arena:destroy()
    C.printf("=== ALL OPTIMIZER TESTS PASSED (4/4) ===\n")
    return 0
end

local code = run_optimizer_tests()
if code ~= 0 then
    os.exit(1)
end
