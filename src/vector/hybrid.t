-- Quarry hybrid relational and vector query executor
-- Filters relational chunks before vector distance evaluation to prune candidate spaces.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local types = require("src.types.type")
local chunk = require("src.storage/chunk")
local dist = require("src.vector/distance")

local DataChunk = chunk.DataChunk

local hybrid = {}

struct HybridCandidate {
    row_idx: uint32,
    distance: float
}

struct HybridQueryExecutor {
    dim: uint32,
    metric: int32
}

terra HybridQueryExecutor:init(dim: uint32, metric: int32)
    self.dim = dim
    self.metric = metric
end

-- Executes hybrid search on a chunk:
-- Evaluates query vector against rows that passed relational filtering (selection vector)
terra HybridQueryExecutor:rank_chunk(c: &DataChunk, vec_col_idx: uint32, query_vec: &float, k: uint32, out_ids: &uint32, out_dists: &float) : uint32
    var col_vec = c:get_column(vec_col_idx)
    if col_vec == nil then return 0 end

    var n = c.num_rows
    var candidates : HybridCandidate[2048]
    var cand_count : uint32 = 0

    for i = 0, n do
        var phys_idx = c:get_row_index(i)
        if not col_vec:is_null(phys_idx) then
            var v_ptr = col_vec:get_vector(phys_idx)
            var d : float = 0.0f
            if self.metric == dist.METRIC_COSINE then
                d = dist.cosine_dist(v_ptr, query_vec, self.dim)
            else
                d = dist.l2(v_ptr, query_vec, self.dim)
            end

            candidates[cand_count].row_idx = phys_idx
            candidates[cand_count].distance = d
            cand_count = cand_count + 1
        end
    end

    -- Sort candidates by distance (ascending)
    for i = 0, cand_count do
        for j = i + 1, cand_count do
            if candidates[j].distance < candidates[i].distance then
                var tmp = candidates[i]
                candidates[i] = candidates[j]
                candidates[j] = tmp
            end
        end
    end

    var return_count = k
    if return_count > cand_count then return_count = cand_count end

    for i = 0, return_count do
        out_ids[i] = candidates[i].row_idx
        out_dists[i] = candidates[i].distance
    end

    return return_count
end

hybrid.HybridCandidate = HybridCandidate
hybrid.HybridQueryExecutor = HybridQueryExecutor
return hybrid
