-- Quarry dense float32 vector subsystem
-- High-dimensional embedding representation and similarity metric kernels.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local simd = require("src.common.simd")

local vec = {}

struct DenseVector {
    dim: uint32,
    data: &float
}

terra DenseVector:init(dim: uint32)
    self.dim = dim
    self.data = [&float](alloc.aligned_alloc(dim * sizeof(float), alloc.CACHE_LINE))
    C.memset(self.data, 0, dim * sizeof(float))
end

terra DenseVector:destroy()
    if self.data ~= nil then
        alloc.aligned_free(self.data)
        self.data = nil
    end
    self.dim = 0
end

terra DenseVector:copy_from(source: &float, dim: uint32)
    var count = dim
    if count > self.dim then count = self.dim end
    C.memcpy(self.data, source, count * sizeof(float))
end

-- Euclidean norm (L2 length)
terra DenseVector:l2_norm() : float
    var sum_sq = simd.dot_product_f32(self.data, self.data, self.dim)
    return C.sqrtf(sum_sq)
end

-- Normalize vector to unit sphere in-place
terra DenseVector:normalize()
    var norm = self:l2_norm()
    if norm > 1e-9f then
        var inv_norm = 1.0f / norm
        for i = 0, self.dim do
            self.data[i] = self.data[i] * inv_norm
        end
    end
end

-- Squared Euclidean distance
terra DenseVector:l2_distance_sq(other: &DenseVector) : float
    var total : float = 0.0f
    var i : uint32 = 0
    var n = self.dim
    if other.dim < n then n = other.dim end

    while i + 4 <= n do
        var va = @[&vector(float, 4)](&(self.data[i]))
        var vb = @[&vector(float, 4)](&(other.data[i]))
        var diff = va - vb
        var sq = diff * diff
        total = total + (sq[0] + sq[1] + sq[2] + sq[3])
        i = i + 4
    end

    while i < n do
        var d = self.data[i] - other.data[i]
        total = total + (d * d)
        i = i + 1
    end

    return total
end

-- Euclidean distance (L2)
terra DenseVector:l2_distance(other: &DenseVector) : float
    return C.sqrtf(self:l2_distance_sq(other))
end

-- Inner dot product
terra DenseVector:dot(other: &DenseVector) : float
    var n = self.dim
    if other.dim < n then n = other.dim end
    return simd.dot_product_f32(self.data, other.data, n)
end

-- Cosine similarity: dot(a, b) / (|a| * |b|)
terra DenseVector:cosine_similarity(other: &DenseVector) : float
    var dot_val = self:dot(other)
    var norm_a = self:l2_norm()
    var norm_b = other:l2_norm()
    var denom = norm_a * norm_b
    if denom < 1e-9f then return 0.0f end
    return dot_val / denom
end

-- Cosine distance: 1.0 - cosine_similarity
terra DenseVector:cosine_distance(other: &DenseVector) : float
    return 1.0f - self:cosine_similarity(other)
end

-- Manhattan distance (L1)
terra DenseVector:manhattan_distance(other: &DenseVector) : float
    var total : float = 0.0f
    var n = self.dim
    if other.dim < n then n = other.dim end
    for i = 0, n do
        total = total + C.fabsf(self.data[i] - other.data[i])
    end
    return total
end

vec.DenseVector = DenseVector
return vec
