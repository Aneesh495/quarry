-- Quarry query planner subsystem
-- Binds AST statements against catalog schemas and synthesizes logical operator trees.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local ast = require("src.parser/ast")
local cat = require("src.storage/catalog")
local plan = require("src.optimizer/logical_plan")

local SelectStmt = ast.SelectStmt
local LogicalOperator = plan.LogicalOperator
local Catalog = cat.Catalog

local planner = {}

struct Planner {
    catalog: &Catalog,
    arena: &alloc.Arena,
    has_error: bool,
    error_msg: int8[256]
}

terra Planner:init(catalog: &Catalog, arena: &alloc.Arena)
    self.catalog = catalog
    self.arena = arena
    self.has_error = false
    self.error_msg[0] = 0
end

terra Planner:set_error(msg: &int8)
    self.has_error = true
    C.strncpy(&(self.error_msg[0]), msg, 255)
    self.error_msg[255] = 0
end

-- Checks if an expression contains aggregate functions (SUM, COUNT, AVG, MIN, MAX)
terra Planner:is_aggregate_expr(expr: &ast.ExprNode) : bool
    if expr == nil then return false end
    if expr.expr_type == ast.EXPR_FUNCTION_CALL then
        var fname = &(expr.func_name[0])
        if C.strcmp(fname, "SUM") == 0 or C.strcmp(fname, "sum") == 0 or
           C.strcmp(fname, "COUNT") == 0 or C.strcmp(fname, "count") == 0 or
           C.strcmp(fname, "AVG") == 0 or C.strcmp(fname, "avg") == 0 or
           C.strcmp(fname, "MIN") == 0 or C.strcmp(fname, "min") == 0 or
           C.strcmp(fname, "MAX") == 0 or C.strcmp(fname, "max") == 0 then
            return true
        end
    end
    if expr.left ~= nil and self:is_aggregate_expr(expr.left) then return true end
    if expr.right ~= nil and self:is_aggregate_expr(expr.right) then return true end
    for i = 0, expr.num_args do
        if self:is_aggregate_expr(expr.args[i]) then return true end
    end
    return false
end

terra Planner:create_logical_plan(sel: &SelectStmt) : &LogicalOperator
    -- 1. Base table scan
    var tname = &(sel.from_table[0])
    var table_ptr = self.catalog:get_table(tname)
    if table_ptr == nil then
        self:set_error("Table referenced in FROM does not exist in catalog")
        return nil
    end

    var scan_op = plan.new_operator(self.arena, plan.LOGICAL_SCAN)
    C.strncpy(&(scan_op.table_name[0]), tname, 63)
    scan_op.num_columns = table_ptr.num_columns
    for i = 0, table_ptr.num_columns do
        scan_op.column_indices[i] = i
        C.strncpy(&(scan_op.column_names[i][0]), &(table_ptr.columns[i].name[0]), 63)
    end
    scan_op.estimated_cardinality = table_ptr.total_rows

    var current_root = scan_op

    -- 2. Optional JOIN
    if sel.has_join then
        var j_tname = &(sel.join_table[0])
        var j_table = self.catalog:get_table(j_tname)
        if j_table == nil then
            self:set_error("Table referenced in JOIN does not exist in catalog")
            return nil
        end

        var j_scan = plan.new_operator(self.arena, plan.LOGICAL_SCAN)
        C.strncpy(&(j_scan.table_name[0]), j_tname, 63)
        j_scan.num_columns = j_table.num_columns
        for i = 0, j_table.num_columns do
            j_scan.column_indices[i] = i
            C.strncpy(&(j_scan.column_names[i][0]), &(j_table.columns[i].name[0]), 63)
        end
        j_scan.estimated_cardinality = j_table.total_rows

        var join_op = plan.new_operator(self.arena, plan.LOGICAL_HASH_JOIN)
        join_op.join_type = sel.join_type
        join_op.join_on = sel.join_on
        join_op.left = current_root
        join_op.right = j_scan
        current_root = join_op
    end

    -- 3. WHERE filter
    if sel.where_clause ~= nil then
        var filter_op = plan.new_operator(self.arena, plan.LOGICAL_FILTER)
        filter_op.predicate = sel.where_clause
        filter_op.left = current_root
        current_root = filter_op
    end

    -- 4. Check for GROUP BY or aggregate projections
    var has_aggs = false
    for i = 0, sel.num_projections do
        if self:is_aggregate_expr(sel.projections[i]) then
            has_aggs = true
            break
        end
    end

    if sel.num_group_by > 0 or has_aggs then
        var agg_op = plan.new_operator(self.arena, plan.LOGICAL_AGGREGATE)
        agg_op.num_group_by = sel.num_group_by
        for i = 0, sel.num_group_by do
            agg_op.group_by[i] = sel.group_by[i]
        end

        var agg_count : uint32 = 0
        for i = 0, sel.num_projections do
            if self:is_aggregate_expr(sel.projections[i]) then
                agg_op.aggregates[agg_count] = sel.projections[i]
                agg_count = agg_count + 1
            end
        end
        agg_op.num_aggregates = agg_count
        agg_op.left = current_root
        current_root = agg_op
    end

    -- 5. HAVING filter
    if sel.having_clause ~= nil then
        var having_op = plan.new_operator(self.arena, plan.LOGICAL_FILTER)
        having_op.predicate = sel.having_clause
        having_op.left = current_root
        current_root = having_op
    end

    -- 6. Projection
    var proj_op = plan.new_operator(self.arena, plan.LOGICAL_PROJECT)
    proj_op.num_projections = sel.num_projections
    for i = 0, sel.num_projections do
        proj_op.projections[i] = sel.projections[i]
        C.strncpy(&(proj_op.aliases[i][0]), &(sel.aliases[i][0]), 63)
    end
    proj_op.left = current_root
    current_root = proj_op

    -- 7. ORDER BY
    if sel.num_order_by > 0 then
        var sort_op = plan.new_operator(self.arena, plan.LOGICAL_SORT)
        sort_op.num_order_by = sel.num_order_by
        for i = 0, sel.num_order_by do
            sort_op.order_by[i] = sel.order_by[i]
            sort_op.order_asc[i] = sel.order_asc[i]
        end
        sort_op.left = current_root
        current_root = sort_op
    end

    -- 8. LIMIT and OFFSET
    if sel.limit_val >= 0 then
        var limit_op = plan.new_operator(self.arena, plan.LOGICAL_LIMIT)
        limit_op.limit_val = sel.limit_val
        limit_op.offset_val = sel.offset_val
        limit_op.left = current_root
        current_root = limit_op
    end

    return current_root
end

planner.Planner = Planner
return planner
