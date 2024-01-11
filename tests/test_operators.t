-- Test suite for Quarry physical scan, filter, project, and limit operators

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")
local token = require("src.parser/token")
local scan = require("src.operators/scan")
local filter = require("src.operators/filter")
local project = require("src.operators/project")
local limit = require("src.operators/limit")

local DataChunk = chunk.DataChunk
local Table = tbl.Table

terra run_operator_tests() : int
    C.printf("=== Running Quarry Physical Operators Tests ===\n")

    -- Setup source table
    var col_names : (&int8)[3]
    col_names[0] = "id"
    col_names[1] = "score"
    col_names[2] = "salary"

    var col_tps : types.DataType[3]
    col_tps[0] = types.make_type(types.INT64, 0)
    col_tps[1] = types.make_type(types.INT64, 0)
    col_tps[2] = types.make_type(types.INT64, 0)

    var my_table : Table
    my_table:init("employees", 3, &(col_names[0]), &(col_tps[0]))

    for i = 0, 100 do
        my_table:append_row_i64_3([int64](i), [int64](i % 10), [int64](i * 1000))
    end

    -- Test 1: Scan
    var s : scan.PhysicalScan
    s:init(&my_table)
    var c = s:get_next_chunk()
    if c == nil or c.num_rows ~= 100 then
        C.printf("FAIL: scan get_next_chunk failed (num_rows=%u)\n", c.num_rows)
        return 1
    end
    C.printf("PASS: PhysicalScan chunk retrieval\n")

    -- Test 2: Filter (score == 5)
    var f : filter.PhysicalFilter
    f:init(nil)
    var matched = f:execute_i64_cmp(c, 1, token.TOKEN_EQ, 5)
    if matched ~= 10 then -- 0..99 has exactly 10 numbers ending in 5
        C.printf("FAIL: filter expected 10 matches, got %u\n", matched)
        return 1
    end
    if c.num_rows ~= 10 or not c.has_selection then
        C.printf("FAIL: chunk selection vector not updated\n")
        return 1
    end
    C.printf("PASS: PhysicalFilter selection vector generation (10 rows matched)\n")

    -- Test 3: Project (compute salary * 1.1)
    var p : project.PhysicalProject
    p:init(2)
    p:set_passthrough(0, 0) -- id -> id
    p:set_scaled_col(1, 2, 1.1) -- salary * 1.1

    var out_c : DataChunk
    var out_tps : types.DataType[2]
    out_tps[0] = types.make_type(types.INT64, 0)
    out_tps[1] = types.make_type(types.DOUBLE, 0)
    out_c:init(2, &(out_tps[0]), 64)

    p:execute(c, &out_c)
    if out_c.num_rows ~= 10 then
        C.printf("FAIL: projection output rows expected 10, got %u\n", out_c.num_rows)
        return 1
    end

    -- First filtered row was id=5, salary=5000, 5000 * 1.1 = 5500.0
    if out_c.columns[0]:get_i64(0) ~= 5 or C.fabs(out_c.columns[1]:get_f64(0) - 5500.0) > 0.01 then
        C.printf("FAIL: projected value mismatch (id=%lld, sal=%f)\n", out_c.columns[0]:get_i64(0), out_c.columns[1]:get_f64(0))
        return 1
    end
    C.printf("PASS: PhysicalProject expression evaluation and column passthrough\n")

    -- Test 4: Limit (LIMIT 3)
    var l : limit.PhysicalLimit
    l:init(3, 0)
    var done = l:apply(&out_c)
    if out_c.num_rows ~= 3 or not done then
        C.printf("FAIL: limit apply expected 3 rows and done=true (got %u)\n", out_c.num_rows)
        return 1
    end
    C.printf("PASS: PhysicalLimit early-stopping truncation\n")

    out_c:destroy()
    my_table:destroy()
    C.printf("=== ALL OPERATORS TESTS PASSED (4/4) ===\n")
    return 0
end

local code = run_operator_tests()
if code ~= 0 then
    os.exit(1)
end
