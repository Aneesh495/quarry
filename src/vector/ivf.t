-- Quarry Inverted File (IVF) vector index subsystem
-- Partitions high-dimensional space into Voronoi centroid clusters for fast inverted search.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local dist = require("src.vector/distance")

local ivf = {}

ivf.MAX_CLUSTERS = 32
ivf.MAX_POSTINGS = 1024

struct ClusterPostingList {
    count: uint32,
    ids: uint32[1024]
}

struct IvfIndex {
    dim: uint32,
    num_clusters: uint32,
    nprobe: uint32,
    centroids: &float,
    clusters: ClusterPostingList[32],
    raw_vectors: &float,
    vector_capacity: uint32,
    total_vectors: uint32
}

terra IvfIndex:init(dim: uint32, num_clusters: uint32, capacity: uint32)
    self.dim = dim
    var k = num_clusters
    if k > 32 then k = 32 end
    if k == 0 then k = 4 end
    self.num_clusters = k
    self.nprobe = 2
    self.vector_capacity = capacity
    self.total_vectors = 0

    self.centroids = [&float](alloc.aligned_alloc(k * dim * sizeof(float), alloc.CACHE_LINE))
    C.memset(self.centroids, 0, k * dim * sizeof(float))

    self.raw_vectors = [&float](alloc.aligned_alloc(capacity * dim * sizeof(float), alloc.CACHE_LINE))

    for i = 0, k do
        self.clusters[i].count = 0
    end
end

terra IvfIndex:destroy()
    if self.centroids ~= nil then
        alloc.aligned_free(self.centroids)
        self.centroids = nil
    end
    if self.raw_vectors ~= nil then
        alloc.aligned_free(self.raw_vectors)
        self.raw_vectors = nil
    end
    self.total_vectors = 0
end

terra IvfIndex:train_centroids(training_data: &float, num_samples: uint32)
    var k = self.num_clusters
    var d = self.dim
    -- Initialize centroids with first K samples
    for c = 0, k do
        var sample_idx = c
        if sample_idx >= num_samples then sample_idx = num_samples - 1 end
        C.memcpy(&(self.centroids[c * d]), &(training_data[sample_idx * d]), d * sizeof(float))
    end
end

terra IvfIndex:find_nearest_centroid(v: &float) : uint32
    var best_cluster : uint32 = 0
    var best_dist : float = 1e30f
    var d = self.dim

    for c = 0, self.num_clusters do
        var dist_sq = dist.l2_sq(v, &(self.centroids[c * d]), d)
        if dist_sq < best_dist then
            best_dist = dist_sq
            best_cluster = c
        end
    end

    return best_cluster
end

terra IvfIndex:add_vector(id: uint32, v: &float) : bool
    if self.total_vectors >= self.vector_capacity then return false end
    var d = self.dim
    var idx = self.total_vectors

    C.memcpy(&(self.raw_vectors[idx * d]), v, d * sizeof(float))

    var c = self:find_nearest_centroid(v)
    if self.clusters[c].count < ivf.MAX_POSTINGS then
        var pos = self.clusters[c].count
        self.clusters[c].ids[pos] = id
        self.clusters[c].count = pos + 1
    end

    self.total_vectors = idx + 1
    return true
end

ivf.ClusterPostingList = ClusterPostingList
ivf.IvfIndex = IvfIndex
return ivf
