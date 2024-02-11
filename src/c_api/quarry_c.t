-- Quarry C Foreign Function Interface implementation
-- Provides standard C ABI symbols for dynamic linking with Python, C, C++, and Go.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local tbl = require("src.storage/table")
local cat = require("src.storage/catalog")
local token = require("src.parser/token")
local ast = require("src.parser/ast")
local parser = require("src.parser/parser")
local plan = require("src.optimizer/logical_plan")
local planner = require("src.optimizer/planner")
local rules = require("src.optimizer/rules")
local scan = require("src.operators/scan")
local filter = require("src.operators/filter")
local project = require("src.operators/project")
local limit = require("src.operators/limit")
local dist = require("src.vector/distance")

local Table = tbl.Table
local Catalog = cat.Catalog
local DataChunk = chunk.DataChunk

local c_api = {}

struct quarry_db {
    catalog: Catalog,
    arena: alloc.Arena
}

struct quarry_stmt {
    db: &quarry_db,
    active_chunk: &DataChunk,
    current_row: uint32,
    total_rows: uint32,
    num_columns: uint32,
    is_completed: bool
}

terra quarry_open(path: &int8) : &quarry_db
    var db = [&quarry_db](C.malloc(sizeof(quarry_db)))
    db.catalog:init()
    db.arena:init(65536)
    return db
end

terra quarry_close(db: &quarry_db)
    if db ~= nil then
        db.catalog:destroy()
        db.arena:destroy()
        C.free(db)
    end
end

terra quarry_exec(db: &quarry_db, sql: &int8) : int32
    if db == nil or sql == nil then return -1 end
    var p : parser.Parser
    p:init(sql, &(db.arena))
    var stmt = p:parse()
    if stmt == nil or p.has_error then return -1 end

    if stmt.stmt_type == ast.STMT_CREATE_TABLE then
        var ct = &(stmt.create_stmt)
        var col_names : (&int8)[32]
        for i = 0, ct.num_columns do
            col_names[i] = &(ct.column_names[i][0])
        end
        var t = db.catalog:create_table(&(ct.table_name[0]), ct.num_columns, &(col_names[0]), &(ct.column_types[0]))
        if t == nil then return -1 end
        return 0
    end

    return 0
end

terra quarry_prepare(db: &quarry_db, sql: &int8) : &quarry_stmt
    if db == nil or sql == nil then return nil end

    var p : parser.Parser
    p:init(sql, &(db.arena))
    var stmt = p:parse()
    if stmt == nil or p.has_error then return nil end

    if stmt.stmt_type ~= ast.STMT_SELECT then return nil end

    var pl : planner.Planner
    pl:init(&(db.catalog), &(db.arena))
    var l_root = pl:create_logical_plan(&(stmt.select_stmt))
    if l_root == nil then return nil end

    var optimized = rules.optimize_plan(l_root)

    var target_table = db.catalog:get_table(&(stmt.select_stmt.from_table[0]))
    if target_table == nil or target_table.num_chunks == 0 then return nil end

    var s = [&quarry_stmt](C.malloc(sizeof(quarry_stmt)))
    s.db = db
    s.active_chunk = target_table:get_chunk(0)
    s.current_row = 0
    s.total_rows = s.active_chunk.num_rows
    s.num_columns = s.active_chunk.num_columns
    s.is_completed = false
    return s
end

terra quarry_step(stmt: &quarry_stmt) : int32
    if stmt == nil or stmt.is_completed then return 101 end -- QUARRY_DONE
    if stmt.current_row < stmt.total_rows then
        stmt.current_row = stmt.current_row + 1
        return 100 -- QUARRY_ROW
    else
        stmt.is_completed = true
        return 101 -- QUARRY_DONE
    end
end

terra quarry_column_count(stmt: &quarry_stmt) : int32
    if stmt == nil then return 0 end
    return [int32](stmt.num_columns)
end

terra quarry_column_int64(stmt: &quarry_stmt, col_idx: int32) : int64
    if stmt == nil or stmt.active_chunk == nil then return 0 end
    var r = stmt.current_row - 1
    var phys_idx = stmt.active_chunk:get_row_index(r)
    return stmt.active_chunk.columns[col_idx]:get_i64(phys_idx)
end

terra quarry_column_double(stmt: &quarry_stmt, col_idx: int32) : double
    if stmt == nil or stmt.active_chunk == nil then return 0.0 end
    var r = stmt.current_row - 1
    var phys_idx = stmt.active_chunk:get_row_index(r)
    return stmt.active_chunk.columns[col_idx]:get_f64(phys_idx)
end

terra quarry_column_text(stmt: &quarry_stmt, col_idx: int32) : &int8
    if stmt == nil or stmt.active_chunk == nil then return "" end
    var r = stmt.current_row - 1
    var phys_idx = stmt.active_chunk:get_row_index(r)
    return stmt.active_chunk.columns[col_idx]:get_string(phys_idx)
end

terra quarry_column_is_null(stmt: &quarry_stmt, col_idx: int32) : int32
    if stmt == nil or stmt.active_chunk == nil then return 1 end
    var r = stmt.current_row - 1
    var phys_idx = stmt.active_chunk:get_row_index(r)
    if stmt.active_chunk.columns[col_idx]:is_null(phys_idx) then
        return 1
    end
    return 0
end

terra quarry_finalize(stmt: &quarry_stmt)
    if stmt ~= nil then
        C.free(stmt)
    end
end

terra quarry_vector_knn(db: &quarry_db, table_name: &int8, vec_col_idx: uint32, query_vec: &float, dim: uint32, k: uint32, out_ids: &uint32, out_dists: &float) : int32
    if db == nil or table_name == nil then return -1 end
    var target = db.catalog:get_table(table_name)
    if target == nil then return -1 end
    if target.num_chunks == 0 then return 0 end

    var c = target:get_chunk(0)
    var col_vec = c:get_column(vec_col_idx)
    if col_vec == nil then return -1 end

    var n = c.num_rows
    var count : uint32 = 0
    if k < n then count = k else count = n end

    for i = 0, count do
        var phys_idx = c:get_row_index(i)
        var v = col_vec:get_vector(phys_idx)
        out_ids[i] = phys_idx
        out_dists[i] = dist.cosine_dist(v, query_vec, dim)
    end

    return [int32](count)
end

c_api.quarry_open = quarry_open
c_api.quarry_close = quarry_close
c_api.quarry_exec = quarry_exec
c_api.quarry_prepare = quarry_prepare
c_api.quarry_step = quarry_step
c_api.quarry_column_count = quarry_column_count
c_api.quarry_column_int64 = quarry_column_int64
c_api.quarry_column_double = quarry_column_double
c_api.quarry_column_text = quarry_column_text
c_api.quarry_column_is_null = quarry_column_is_null
c_api.quarry_finalize = quarry_finalize
c_api.quarry_vector_knn = quarry_vector_knn

return c_api
