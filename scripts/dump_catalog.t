-- dump_catalog.t
-- Schema and catalog introspection tool for Quarry database
-- Formats relational schemas, chunk metadata, and memory footprint.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local tbl = require("src.storage/table")
local cat = require("src.storage/catalog")

terra print_type_name(tid: int32) : &int8
    if tid == types.INT64 then return "BIGINT"
    elseif tid == types.INT32 then return "INTEGER"
    elseif tid == types.DOUBLE then return "DOUBLE"
    elseif tid == types.FLOAT then return "FLOAT"
    elseif tid == types.VARCHAR then return "VARCHAR"
    elseif tid == types.VECTOR_F32 then return "VECTOR"
    elseif tid == types.BOOL then return "BOOLEAN"
    else return "UNKNOWN" end
end

terra dump_table_schema(t: &tbl.Table)
    C.printf("\nTable: %s\n", &(t.name[0]))
    C.printf("Chunks: %u | Total Rows: %llu\n", t.num_chunks, t.total_rows)
    C.printf("+----+-----------------------+------------+------------+\n")
    C.printf("| #  | Column Name           | Data Type  | Width (B)  |\n")
    C.printf("+----+-----------------------+------------+------------+\n")

    for i = 0, t.num_columns do
        var cname = &(t.columns[i].name[0])
        var ctype = t.columns[i].data_type
        var tname = print_type_name(ctype.type_id)
        C.printf("| %-2u | %-21s | %-10s | %10u |\n", i, cname, tname, ctype.byte_width)
    end
    C.printf("+----+-----------------------+------------+------------+\n")
end

terra run_dump() : int
    C.printf("=================================================================\n")
    C.printf("  QUARRY CATALOG & SCHEMA METADATA DUMP\n")
    C.printf("=================================================================\n")

    var my_cat : cat.Catalog
    my_cat:init()

    -- 1. Table lineitem
    var li_cols : (&int8)[5]
    li_cols[0] = "l_orderkey"
    li_cols[1] = "l_partkey"
    li_cols[2] = "l_quantity"
    li_cols[3] = "l_extendedprice"
    li_cols[4] = "l_discount"

    var li_tps : types.DataType[5]
    li_tps[0] = types.make_type(types.INT64, 0)
    li_tps[1] = types.make_type(types.INT64, 0)
    li_tps[2] = types.make_type(types.INT64, 0)
    li_tps[3] = types.make_type(types.DOUBLE, 0)
    li_tps[4] = types.make_type(types.DOUBLE, 0)

    var t_li = my_cat:create_table("lineitem", 5, &(li_cols[0]), &(li_tps[0]))

    -- 2. Table document_embeddings
    var emb_cols : (&int8)[3]
    emb_cols[0] = "doc_id"
    emb_cols[1] = "title"
    emb_cols[2] = "embedding"

    var emb_tps : types.DataType[3]
    emb_tps[0] = types.make_type(types.INT64, 0)
    emb_tps[1] = types.make_type(types.VARCHAR, 0)
    emb_tps[2] = types.make_type(types.VECTOR_F32, 384)

    var t_emb = my_cat:create_table("document_embeddings", 3, &(emb_cols[0]), &(emb_tps[0]))

    C.printf("Total Registered Tables: %u\n", my_cat.num_tables)

    dump_table_schema(t_li)
    dump_table_schema(t_emb)

    C.printf("=================================================================\n")
    my_cat:destroy()
    return 0
end

local code = run_dump()
if code ~= 0 then os.exit(1) end
