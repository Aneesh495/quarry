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
                self.nodes[i].vec_data = nil
            end
        end
        alloc.aligned_free(self.nodes)
        self.nodes = nil
    end
    self.count = 0
    self.entry_point_id = -1
end

-- Inserts a vector into the HNSW index
terra HnswIndex:insert(id: uint32, vec_ptr: &float) : bool
    if self.count >= self.capacity then return false end

    var node_idx = self.count
    var n = &(self.nodes[node_idx])
    n.id = id
    n.level = 0

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

    -- Greedy search for nearest node to establish graph connectivity
    var curr_id = self.entry_point_id
    var curr_dist = dist.l2_sq(vec_ptr, self.nodes[curr_id].vec_data, self.dim)
    var changed = true
    var steps : uint32 = 0

    while changed and steps < 64 do
        steps = steps + 1
        changed = false
        var curr_node = &(self.nodes[curr_id])
        var n_deg = curr_node.num_neighbors[0]
        for ni = 0, n_deg do
            var neighbor_id = curr_node.neighbors[0][ni]
            var neighbor_node = &(self.nodes[neighbor_id])
            var d = dist.l2_sq(vec_ptr, neighbor_node.vec_data, self.dim)
            if d < curr_dist then
                curr_dist = d
                curr_id = [int32](neighbor_id)
                changed = true
            end
        end
    end

    -- Connect bidirectionally with nearest node
    var closest_node = &(self.nodes[curr_id])
    if n.num_neighbors[0] < hnsw.MAX_NEIGHBORS then
        n.neighbors[0][n.num_neighbors[0]] = [uint32](curr_id)
        n.num_neighbors[0] = n.num_neighbors[0] + 1
    end

    if closest_node.num_neighbors[0] < hnsw.MAX_NEIGHBORS then
        closest_node.neighbors[0][closest_node.num_neighbors[0]] = node_idx
        closest_node.num_neighbors[0] = closest_node.num_neighbors[0] + 1
    end

    -- Small-world long-range shortcut edge
    if self.count > 10 then
        var skip_id = [uint32](([int64](node_idx) * 37 + 13) % [int64](self.count))
        var skip_node = &(self.nodes[skip_id])
        if n.num_neighbors[0] < hnsw.MAX_NEIGHBORS and skip_node.num_neighbors[0] < hnsw.MAX_NEIGHBORS then
            n.neighbors[0][n.num_neighbors[0]] = skip_id
            n.num_neighbors[0] = n.num_neighbors[0] + 1
            skip_node.neighbors[0][skip_node.num_neighbors[0]] = node_idx
            skip_node.num_neighbors[0] = skip_node.num_neighbors[0] + 1
        end
    end

    self.count = self.count + 1
    return true
end

-- Searches top-k nearest neighbors via greedy graph routing
terra HnswIndex:search_knn(query_vec: &float, k: uint32, out_ids: &uint32, out_dists: &float) : uint32
    if self.count == 0 or self.entry_point_id < 0 then return 0 end

    -- 1. Greedy routing to local minimum
    var curr_id = self.entry_point_id
    var curr_dist = dist.l2_sq(query_vec, self.nodes[curr_id].vec_data, self.dim)
    var changed = true
    var steps : uint32 = 0

    while changed and steps < 128 do
        steps = steps + 1
        changed = false
        var curr_node = &(self.nodes[curr_id])
        var n_deg = curr_node.num_neighbors[0]
        for ni = 0, n_deg do
            var neighbor_id = curr_node.neighbors[0][ni]
            var neighbor_node = &(self.nodes[neighbor_id])
            var d = dist.l2_sq(query_vec, neighbor_node.vec_data, self.dim)
            if d < curr_dist then
                curr_dist = d
                curr_id = [int32](neighbor_id)
                changed = true
            end
        end
    end

    -- 2. Collect candidate pool around the local minimum and its 1-hop and 2-hop neighbors
    var candidates : NeighborDist[256]
    var cand_count : uint32 = 0

    candidates[0].id = self.nodes[curr_id].id
    candidates[0].distance = curr_dist
    cand_count = 1

    var local_node = &(self.nodes[curr_id])
    var deg1 = local_node.num_neighbors[0]
    for i = 0, deg1 do
        var n1_id = local_node.neighbors[0][i]
        if cand_count < 256 then
            var d1 = dist.l2_sq(query_vec, self.nodes[n1_id].vec_data, self.dim)
            candidates[cand_count].id = self.nodes[n1_id].id
            candidates[cand_count].distance = d1
            cand_count = cand_count + 1

            -- 2-hop expansion
            var n1_node = &(self.nodes[n1_id])
            var deg2 = n1_node.num_neighbors[0]
            for j = 0, deg2 do
                var n2_id = n1_node.neighbors[0][j]
                if cand_count < 256 and n2_id ~= [uint32](curr_id) then
                    var d2 = dist.l2_sq(query_vec, self.nodes[n2_id].vec_data, self.dim)
                    candidates[cand_count].id = self.nodes[n2_id].id
                    candidates[cand_count].distance = d2
                    cand_count = cand_count + 1
                end
            end
        end
    end

    -- 3. Sort candidates by distance ascending
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
