-- Quarry interactive SQL REPL and query execution console
-- Provides formatted ASCII tables, schema introspection, and execution profiling.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")
local cat = require("src.storage/catalog")
local timer = require("src.common.timer")
local c_api = require("src.c_api/quarry_c")

local cli = {}

terra cli.print_banner()
    C.printf("\n")
    C.printf("   ____  __  ______ _____  ______  __\n")
    C.printf("  / __ \\/ / / / __ `/ __ \\/ __ \\ \\/ /\n")
    C.printf(" / /_/ / /_/ / /_/ / / / / /_/ /\\  / \n")
    C.printf(" \\___\\_\\____/\\__,_/_/ /_/\\____/ /_/  \n")
    C.printf("\n")
    C.printf(" Quarry Columnar OLAP Engine & Vector Database (v1.0.0)\n")
    C.printf(" Type '.help' for commands, SQL terminated by ';' to execute.\n\n")
end

terra cli.print_help()
    C.printf("Quarry Interactive Shell Commands:\n")
    C.printf("  .tables          List registered tables in the catalog\n")
    C.printf("  .schema <name>   Display schema of specified table\n")
    C.printf("  .timer on|off    Toggle execution timing display\n")
    C.printf("  .help            Display this help message\n")
    C.printf("  .quit / .exit    Exit the Quarry shell\n")
end

terra cli.print_table_row(c: &chunk.DataChunk, row_idx: uint32)
    C.printf("|")
    for i = 0, c.num_columns do
        var col_ptr = c:get_column(i)
        var phys_idx = c:get_row_index(row_idx)

        if col_ptr:is_null(phys_idx) then
            C.printf(" %-12s |", "NULL")
        else
            var tid = col_ptr.data_type.type_id
            if tid == types.VARCHAR then
                C.printf(" %-12s |", col_ptr:get_string(phys_idx))
            elseif tid == types.FLOAT or tid == types.DOUBLE then
                C.printf(" %-12.2f |", col_ptr:get_f64(phys_idx))
            else
                C.printf(" %-12lld |", col_ptr:get_i64(phys_idx))
            end
        end
    end
    C.printf("\n")
end

terra cli.format_result(c: &chunk.DataChunk)
    if c == nil or c.num_rows == 0 then
        C.printf("(0 rows)\n")
        return
    end

    -- Header border
    C.printf("+")
    for i = 0, c.num_columns do
        C.printf("--------------+")
    end
    C.printf("\n|")

    -- Column headers
    for i = 0, c.num_columns do
        var name_buf : int8[16]
        C.snprintf(&(name_buf[0]), 15, "col_%u", i)
        C.printf(" %-12s |", &(name_buf[0]))
    end
    C.printf("\n+")

    for i = 0, c.num_columns do
        C.printf("--------------+")
    end
    C.printf("\n")

    -- Rows
    for r = 0, c.num_rows do
        cli.print_table_row(c, r)
    end

    -- Bottom border
    C.printf("+")
    for i = 0, c.num_columns do
        C.printf("--------------+")
    end
    C.printf("\n(%u rows)\n\n", c.num_rows)
end

return cli
