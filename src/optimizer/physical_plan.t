-- Quarry physical execution plan subsystem
-- Maps logical operator trees to physical pipelines and identifies pipeline breaker boundaries.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local plan = require("src.optimizer/logical_plan")

local LogicalOperator = plan.LogicalOperator

local phys = {}

phys.PHYS_SCAN         = 1
phys.PHYS_FILTER       = 2
phys.PHYS_PROJECT      = 3
phys.PHYS_HASH_JOIN    = 4
phys.PHYS_HASH_AGG     = 5
phys.PHYS_SORT         = 6
phys.PHYS_LIMIT        = 7
phys.PHYS_VECTOR_KNN   = 8

struct PhysicalOperator {
    phys_type: int32,
    pipeline_id: uint32,
    is_pipeline_breaker: bool,
    logical_op: &LogicalOperator,
    left: &PhysicalOperator,
    right: &PhysicalOperator
}

terra PhysicalOperator:init(ptype: int32, log_op: &LogicalOperator)
    self.phys_type = ptype
    self.pipeline_id = 0
    self.is_pipeline_breaker = false
    self.logical_op = log_op
    self.left = nil
    self.right = nil

    if ptype == phys.PHYS_HASH_JOIN or ptype == phys.PHYS_HASH_AGG or ptype == phys.PHYS_SORT then
        self.is_pipeline_breaker = true
    end
end

terra PhysicalOperator:name() : &int8
    var t = self.phys_type
    if t == phys.PHYS_SCAN then return "PhysicalScan"
    elseif t == phys.PHYS_FILTER then return "PhysicalFilter"
    elseif t == phys.PHYS_PROJECT then return "PhysicalProject"
    elseif t == phys.PHYS_HASH_JOIN then return "PhysicalHashJoin"
    elseif t == phys.PHYS_HASH_AGG then return "PhysicalHashAggregate"
    elseif t == phys.PHYS_SORT then return "PhysicalSort"
    elseif t == phys.PHYS_LIMIT then return "PhysicalLimit"
    elseif t == phys.PHYS_VECTOR_KNN then return "PhysicalVectorKNN"
    else return "UnknownPhysOp"
    end
end

-- Constructs physical plan tree from optimized logical plan
local terra create_physical_plan_fn(arena: &alloc.Arena, logical_root: &LogicalOperator, current_pipe_id: &uint32) : &PhysicalOperator
    if logical_root == nil then return nil end

    var ptype = logical_root.op_type -- maps 1:1 to phys_type enum
    var pop = [&PhysicalOperator](arena:allocate(sizeof(PhysicalOperator), 8))
    pop:init(ptype, logical_root)
    pop.pipeline_id = @current_pipe_id

    if pop.is_pipeline_breaker then
        @current_pipe_id = @current_pipe_id + 1
    end

    if logical_root.left ~= nil then
        pop.left = create_physical_plan_fn(arena, logical_root.left, current_pipe_id)
    end
    if logical_root.right ~= nil then
        pop.right = create_physical_plan_fn(arena, logical_root.right, current_pipe_id)
    end

    return pop
end

phys.PhysicalOperator = PhysicalOperator
phys.create_physical_plan = create_physical_plan_fn
return phys
