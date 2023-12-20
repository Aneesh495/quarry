-- Quarry SQL Abstract Syntax Tree (AST) definitions
-- Defines strongly typed expression nodes and statement trees for query optimization.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local value = require("src.types.value")

local Value = value.Value
local DataType = types.DataType

local ast = {}

-- Expression node types
ast.EXPR_LITERAL        = 1
ast.EXPR_COLUMN_REF     = 2
ast.EXPR_BINARY_OP      = 3
ast.EXPR_UNARY_OP       = 4
ast.EXPR_FUNCTION_CALL  = 5
ast.EXPR_CAST           = 6

-- Statement types
ast.STMT_SELECT         = 10
ast.STMT_CREATE_TABLE   = 11
ast.STMT_INSERT         = 12
ast.STMT_COPY           = 13
ast.STMT_EXPLAIN        = 14

-- Join types
ast.JOIN_INNER          = 1
ast.JOIN_LEFT           = 2
ast.JOIN_RIGHT          = 3

struct ExprNode {
    expr_type: int32,
    data_type: DataType,
    op: int32,
    column_name: int8[64],
    table_name: int8[64],
    literal: Value,
    func_name: int8[64],
    left: &ExprNode,
    right: &ExprNode,
    args: (&ExprNode)[8],
    num_args: uint32
}

struct SelectStmt {
    is_explain: bool,
    is_jit: bool,
    from_table: int8[64],
    from_alias: int8[64],
    projections: (&ExprNode)[32],
    aliases: (int8[64])[32],
    num_projections: uint32,
    where_clause: &ExprNode,
    group_by: (&ExprNode)[16],
    num_group_by: uint32,
    having_clause: &ExprNode,
    order_by: (&ExprNode)[16],
    order_asc: bool[16],
    num_order_by: uint32,
    limit_val: int64,
    offset_val: int64,
    has_join: bool,
    join_type: int32,
    join_table: int8[64],
    join_on: &ExprNode
}

struct CreateTableStmt {
    table_name: int8[64],
    column_names: (int8[64])[32],
    column_types: DataType[32],
    num_columns: uint32
}

struct InsertStmt {
    table_name: int8[64],
    values: Value[32],
    num_values: uint32
}

struct CopyStmt {
    table_name: int8[64],
    file_path: int8[128],
    is_from: bool
}

struct Statement {
    stmt_type: int32,
    union {
        select_stmt: SelectStmt,
        create_stmt: CreateTableStmt,
        insert_stmt: InsertStmt,
        copy_stmt: CopyStmt
    }
}

-- AST node constructors allocating from Arena
local terra new_expr_fn(arena: &alloc.Arena, etype: int32) : &ExprNode
    var node = [&ExprNode](arena:allocate(sizeof(ExprNode), 8))
    C.memset(node, 0, sizeof(ExprNode))
    node.expr_type = etype
    return node
end

local terra new_col_ref_fn(arena: &alloc.Arena, tbl: &int8, col: &int8) : &ExprNode
    var node = new_expr_fn(arena, ast.EXPR_COLUMN_REF)
    if tbl ~= nil then
        C.strncpy(&(node.table_name[0]), tbl, 63)
    end
    if col ~= nil then
        C.strncpy(&(node.column_name[0]), col, 63)
    end
    return node
end

local terra new_literal_fn(arena: &alloc.Arena, val: &Value) : &ExprNode
    var node = new_expr_fn(arena, ast.EXPR_LITERAL)
    node.literal = @val
    return node
end

local terra new_binary_op_fn(arena: &alloc.Arena, op: int32, left: &ExprNode, right: &ExprNode) : &ExprNode
    var node = new_expr_fn(arena, ast.EXPR_BINARY_OP)
    node.op = op
    node.left = left
    node.right = right
    return node
end

local terra new_func_call_fn(arena: &alloc.Arena, name: &int8, num_args: uint32, args: &(&ExprNode)) : &ExprNode
    var node = new_expr_fn(arena, ast.EXPR_FUNCTION_CALL)
    if name ~= nil then
        C.strncpy(&(node.func_name[0]), name, 63)
    end
    node.num_args = num_args
    for i = 0, num_args do
        node.args[i] = args[i]
    end
    return node
end

ast.ExprNode = ExprNode
ast.SelectStmt = SelectStmt
ast.CreateTableStmt = CreateTableStmt
ast.InsertStmt = InsertStmt
ast.CopyStmt = CopyStmt
ast.Statement = Statement

ast.new_expr = new_expr_fn
ast.new_col_ref = new_col_ref_fn
ast.new_literal = new_literal_fn
ast.new_binary_op = new_binary_op_fn
ast.new_func_call = new_func_call_fn

return ast
