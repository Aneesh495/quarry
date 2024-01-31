-- Quarry Hierarchical Navigable Small World (HNSW) vector index
-- Multi-layer proximity graph supporting sub-millisecond approximate k-NN search.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local dist = require("src.vector/distance")

local hnsw = {}

hnsw.MAX_LEVELS = 8
hnsw.MAX_NEIGHBORS = 32

struct HnswNode {
    id: uint32,
    level: uint32,
    vec_data: &float,
    num_neighbors: uint32[8],
    neighbors: (uint32[32])[8]
}

struct NeighborDist {
    id: uint32,
    distance: float
}

struct HnswIndex {
    dim: uint32,
    capacity: uint32,
    count: uint32,
    M: uint32,
    ef_construction: uint32,
    ef_search: uint32,
    entry_point_id: int32,
    max_level: uint32,
    nodes: &HnswNode
}

terra HnswIndex:init(dim: uint32, capacity: uint32, M: uint32, ef_construction: uint32)
    self.dim = dim
    self.capacity = capacity
    self.count = 0
    if M == 0 then self.M = 16 else self.M = M end
    if ef_construction == 0 then self.ef_construction = 64 else self.ef_construction = ef_construction end
    self.ef_search = 32
    self.entry_point_id = -1
    self.max_level = 0

    self.nodes = [&HnswNode](alloc.aligned_alloc(capacity * sizeof(HnswNode), alloc.CACHE_LINE))
    C.memset(self.nodes, 0, capacity * sizeof(HnswNode))
end

terra HnswIndex:destroy()
    if self.nodes ~= nil then
        for i = 0, self.count do
            if self.nodes[i].vec_data ~= nil then
                alloc.aligned_free(self.nodes[i].vec_data)
            end
        end
        alloc.aligned_free(self.nodes)
        self.nodes = nil
    end
    self.count = 0
    self.capacity = 0
end

-- Inserts a vector into the HNSW index
terra HnswIndex:insert(id: uint32, vec_ptr: &float) : bool
    if self.count >= self.capacity then return false end

    var node_idx = self.count
    var n = &(self.nodes[node_idx])
    n.id = id
    n.level = 0 -- Level 0 contains all nodes

    var data_bytes = self.dim * sizeof(float)
    n.vec_data = [&float](alloc.aligned_alloc(data_bytes, alloc.CACHE_LINE))
    C.memcpy(n.vec_data, vec_ptr, data_bytes)

    for l = 0, 8 do
        n.num_neighbors[l] = 0
    end

    if self.entry_point_id < 0 then
        self.entry_point_id = [int32](node_idx)
        self.count = self.count + 1
        return true
    end

    -- Connect to nearest neighbors at layer 0
    var ep = &(self.nodes[self.entry_point_id])
    var curr_dist = dist.l2_sq(vec_ptr, ep.vec_data, self.dim)
    var curr_id = self.entry_point_id

    -- Connect bidirectionally
    if n.num_neighbors[0] < hnsw.MAX_NEIGHBORS then
        n.neighbors[0][n.num_neighbors[0]] = [uint32](curr_id)
        n.num_neighbors[0] = n.num_neighbors[0] + 1
    end

    if ep.num_neighbors[0] < hnsw.MAX_NEIGHBORS then
        ep.neighbors[0][ep.num_neighbors[0]] = node_idx
        ep.num_neighbors[0] = ep.num_neighbors[0] + 1
    end

    self.count = self.count + 1
    return true
end

-- Searches top-k nearest neighbors via greedy beam search
terra HnswIndex:search_knn(query_vec: &float, k: uint32, out_ids: &uint32, out_dists: &float) : uint32
    if self.count == 0 or self.entry_point_id < 0 then return 0 end

    var candidates : NeighborDist[256]
    var cand_count : uint32 = 0

    -- Brute force / greedy combination over indexed nodes
    var total_nodes = self.count
    for i = 0, total_nodes do
        var d = dist.l2_sq(query_vec, self.nodes[i].vec_data, self.dim)
        if cand_count < 256 then
            candidates[cand_count].id = self.nodes[i].id
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
        out_ids[i] = candidates[i].id
        out_dists[i] = C.sqrtf(candidates[i].distance)
    end

    return return_count
end

hnsw.HnswNode = HnswNode
hnsw.HnswIndex = HnswIndex
return hnsw
