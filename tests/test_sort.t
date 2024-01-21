-- Test suite for Quarry physical sort and window operators

local C = require("src.common.c").C
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local sort = require("src.operators/sort")
local win = require("src.operators/window")

local DataChunk = chunk.DataChunk

terra run_sort_tests() : int
    C.printf("=== Running Quarry Sort and Window Tests ===\n")

    -- Setup chunk with unsorted integers: 50, 10, 40, 20, 30
    var c : DataChunk
    var dt : types.DataType[2]
    dt[0] = types.make_type(types.INT64, 0)
    dt[1] = types.make_type(types.INT64, 0) -- window column
    c:init(2, &(dt[0]), 16)

    c.columns[0]:set_i64(0, 50)
    c.columns[0]:set_i64(1, 10)
    c.columns[0]:set_i64(2, 40)
    c.columns[0]:set_i64(3, 20)
    c.columns[0]:set_i64(4, 30)
    c.num_rows = 5

    -- Test 1: Ascending Sort
    var s_asc : sort.PhysicalSort
    s_asc:init(16, 0, true)
    s_asc:sink(&c)
    s_asc:execute_sort()
    s_asc:emit_selection(&c)

    if c.num_rows ~= 5 or not c.has_selection then
        C.printf("FAIL: sort selection not set\n")
        return 1
    end

    var expected_asc : int64[5]
    expected_asc[0] = 10; expected_asc[1] = 20; expected_asc[2] = 30; expected_asc[3] = 40; expected_asc[4] = 50
    for i = 0, 5 do
        var phys_idx = c:get_row_index(i)
        if c.columns[0]:get_i64(phys_idx) ~= expected_asc[i] then
            C.printf("FAIL: ascending sort mismatch at %u\n", i)
            return 1
        end
    end
    C.printf("PASS: PhysicalSort ascending order with selection vector indexing\n")

    -- Test 2: Window ROW_NUMBER() on sorted chunk
    var w_row : win.PhysicalWindow
    w_row:init(win.WIN_ROW_NUMBER, 0)
    w_row:execute(&c, 1)

    for i = 0, 5 do
        var phys_idx = c:get_row_index(i)
        if c.columns[1]:get_i64(phys_idx) ~= [int64](i + 1) then
            C.printf("FAIL: ROW_NUMBER mismatch at %u\n", i)
            return 1
        end
    end
    C.printf("PASS: PhysicalWindow ROW_NUMBER() over ordered stream\n")

    c:destroy()
    s_asc:destroy()

    C.printf("=== ALL SORT AND WINDOW TESTS PASSED (2/2) ===\n")
    return 0
end

local code = run_sort_tests()
if code ~= 0 then
    os.exit(1)
end
