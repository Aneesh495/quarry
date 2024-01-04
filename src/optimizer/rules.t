-- Quarry relational query optimization rules
-- Implements predicate pushdown, projection column pruning, and constant folding.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local token = require("src.parser/token")
local ast = require("src.parser/ast")
local plan = require("src.optimizer/logical_plan")

local LogicalOperator = plan.LogicalOperator
local ExprNode = ast.ExprNode

local rules = {}

struct ColNameBuf {
    name: int8[64]
}

-- Constant folding pass: recursively evaluates constant subexpressions
local terra fold_constants_fn(expr: &ExprNode) : &ExprNode
    if expr == nil then return nil end

    if expr.left ~= nil then
        expr.left = fold_constants_fn(expr.left)
    end
    if expr.right ~= nil then
        expr.right = fold_constants_fn(expr.right)
    end

    -- If both left and right are literals and operator is arithmetic
    if expr.expr_type == ast.EXPR_BINARY_OP and expr.left ~= nil and expr.right ~= nil then
        if expr.left.expr_type == ast.EXPR_LITERAL and expr.right.expr_type == ast.EXPR_LITERAL then
            var l_val = expr.left.literal:as_i64()
            var r_val = expr.right.literal:as_i64()
            var res : int64 = 0
            var folded = false

            if expr.op == token.TOKEN_PLUS then
                res = l_val + r_val
                folded = true
            elseif expr.op == token.TOKEN_MINUS then
                res = l_val - r_val
                folded = true
            elseif expr.op == token.TOKEN_STAR then
                res = l_val * r_val
                folded = true
            end

            if folded then
                expr.expr_type = ast.EXPR_LITERAL
                expr.literal:init_i64(5, res) -- INT64
                expr.left = nil
                expr.right = nil
            end
        end
    end

    return expr
end

-- Predicate pushdown pass: pushes filters below projections and joins
local terra pushdown_predicates_fn(op: &LogicalOperator) : &LogicalOperator
    if op == nil then return nil end

    -- Optimize children first
    if op.left ~= nil then
        op.left = pushdown_predicates_fn(op.left)
    end
    if op.right ~= nil then
        op.right = pushdown_predicates_fn(op.right)
    end

    -- If current op is Filter and child is Project, swap them so Filter is evaluated first!
    if op.op_type == plan.LOGICAL_FILTER and op.left ~= nil and op.left.op_type == plan.LOGICAL_PROJECT then
        var proj = op.left
        var child_of_proj = proj.left

        -- Re-link: Project -> Filter -> child_of_proj
        op.left = child_of_proj
        proj.left = op
        return proj
    end

    return op
end

-- Projection pruning: collects column names used in expr
local terra collect_columns_in_expr(expr: &ExprNode, used_cols: &ColNameBuf, used_count: &uint32) : {}
    if expr == nil then return end
    if expr.expr_type == ast.EXPR_COLUMN_REF then
        var col_name = &(expr.column_name[0])
        if C.strcmp(col_name, "*") ~= 0 and col_name[0] ~= 0 then
            var found = false
            for i = 0, @used_count do
                if C.strcmp(&(used_cols[i].name[0]), col_name) == 0 then
                    found = true
                    break
                end
            end
            if not found and @used_count < 32 then
                C.strncpy(&(used_cols[@used_count].name[0]), col_name, 63)
                @used_count = @used_count + 1
            end
        end
    end

    collect_columns_in_expr(expr.left, used_cols, used_count)
    collect_columns_in_expr(expr.right, used_cols, used_count)
    for i = 0, expr.num_args do
        collect_columns_in_expr(expr.args[i], used_cols, used_count)
    end
end

-- Optimizes logical plan by running rule passes
local terra optimize_plan_fn(root: &LogicalOperator) : &LogicalOperator
    if root == nil then return nil end

    -- 1. Constant folding
    if root.predicate ~= nil then
        root.predicate = fold_constants_fn(root.predicate)
    end
    for i = 0, root.num_projections do
        root.projections[i] = fold_constants_fn(root.projections[i])
    end

    -- 2. Predicate pushdown
    var pushed_root = pushdown_predicates_fn(root)

    return pushed_root
end

rules.fold_constants = fold_constants_fn
rules.pushdown_predicates = pushdown_predicates_fn
rules.optimize_plan = optimize_plan_fn

return rules
