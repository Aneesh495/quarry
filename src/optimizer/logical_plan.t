-- Quarry logical query plan subsystem
-- Defines relational algebra tree operators and plan formatting for EXPLAIN.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local ast = require("src.parser/ast")

local ExprNode = ast.ExprNode

local plan = {}

plan.LOGICAL_SCAN       = 1
plan.LOGICAL_FILTER     = 2
plan.LOGICAL_PROJECT    = 3
plan.LOGICAL_HASH_JOIN  = 4
plan.LOGICAL_AGGREGATE  = 5
plan.LOGICAL_SORT       = 6
plan.LOGICAL_LIMIT      = 7
plan.LOGICAL_VECTOR_KNN = 8

struct LogicalOperator {
    op_type: int32,
    table_name: int8[64],
    column_indices: uint32[32],
    column_names: (int8[64])[32],
    num_columns: uint32,
    predicate: &ExprNode,
    projections: (&ExprNode)[32],
    aliases: (int8[64])[32],
    num_projections: uint32,
    group_by: (&ExprNode)[16],
    num_group_by: uint32,
    aggregates: (&ExprNode)[16],
    num_aggregates: uint32,
    order_by: (&ExprNode)[16],
    order_asc: bool[16],
    num_order_by: uint32,
    limit_val: int64,
    offset_val: int64,
    join_type: int32,
    join_on: &ExprNode,
    left: &LogicalOperator,
    right: &LogicalOperator,
    estimated_cardinality: uint64,
    estimated_cost: double
}

terra LogicalOperator:init(op_type: int32)
    C.memset(self, 0, sizeof(LogicalOperator))
    self.op_type = op_type
    self.limit_val = -1
end

terra LogicalOperator:name() : &int8
    var t = self.op_type
    if t == plan.LOGICAL_SCAN then return "LogicalScan"
    elseif t == plan.LOGICAL_FILTER then return "LogicalFilter"
    elseif t == plan.LOGICAL_PROJECT then return "LogicalProject"
    elseif t == plan.LOGICAL_HASH_JOIN then return "LogicalHashJoin"
    elseif t == plan.LOGICAL_AGGREGATE then return "LogicalAggregate"
    elseif t == plan.LOGICAL_SORT then return "LogicalSort"
    elseif t == plan.LOGICAL_LIMIT then return "LogicalLimit"
    elseif t == plan.LOGICAL_VECTOR_KNN then return "LogicalVectorKNN"
    else return "UnknownOp"
    end
end

-- Formats a text representation of the plan tree with indentation
terra LogicalOperator:explain(buf: &int8, max_len: C.size_t, indent: uint32) : int32
    var offset : int32 = 0
    for i = 0, indent do
        offset = offset + C.snprintf(buf + offset, max_len - offset, "  ")
    end

    offset = offset + C.snprintf(buf + offset, max_len - offset, "-> %s", self:name())

    if self.op_type == plan.LOGICAL_SCAN then
        offset = offset + C.snprintf(buf + offset, max_len - offset, " [table=%s, cols=%u]", &(self.table_name[0]), self.num_columns)
    elseif self.op_type == plan.LOGICAL_LIMIT then
        offset = offset + C.snprintf(buf + offset, max_len - offset, " [limit=%lld, offset=%lld]", self.limit_val, self.offset_val)
    elseif self.op_type == plan.LOGICAL_AGGREGATE then
        offset = offset + C.snprintf(buf + offset, max_len - offset, " [group_by=%u, aggs=%u]", self.num_group_by, self.num_aggregates)
    end

    offset = offset + C.snprintf(buf + offset, max_len - offset, "\n")

    if self.left ~= nil then
        offset = offset + self.left:explain(buf + offset, max_len - offset, indent + 1)
    end
    if self.right ~= nil then
        offset = offset + self.right:explain(buf + offset, max_len - offset, indent + 1)
    end

    return offset
end

local terra new_operator_fn(arena: &alloc.Arena, op_type: int32) : &LogicalOperator
    var op = [&LogicalOperator](arena:allocate(sizeof(LogicalOperator), 8))
    op:init(op_type)
    return op
end

plan.LogicalOperator = LogicalOperator
plan.new_operator = new_operator_fn
return plan
