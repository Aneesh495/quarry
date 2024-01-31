-- Quarry SIMD vector distance kernels
-- Hardware-accelerated Euclidean, Cosine, and Dot Product distance metrics.

local C = require("src.common.c").C

local dist = {}

dist.METRIC_L2_SQ   = 1
dist.METRIC_L2      = 2
dist.METRIC_COSINE  = 3
dist.METRIC_DOT     = 4
dist.METRIC_L1      = 5

-- Squared Euclidean distance with 4-wide SIMD unrolling
local terra l2_sq_fn(a: &float, b: &float, dim: uint32) : float
    var total : float = 0.0f
    var i : uint32 = 0

    while i + 4 <= dim do
        var va = @[&vector(float, 4)](&(a[i]))
        var vb = @[&vector(float, 4)](&(b[i]))
        var diff = va - vb
        var sq = diff * diff
        total = total + (sq[0] + sq[1] + sq[2] + sq[3])
        i = i + 4
    end

    while i < dim do
        var d = a[i] - b[i]
        total = total + (d * d)
        i = i + 1
    end

    return total
end

-- Euclidean distance (L2)
local terra l2_fn(a: &float, b: &float, dim: uint32) : float
    return C.sqrtf(l2_sq_fn(a, b, dim))
end

-- Dot product with 4-wide SIMD unrolling
local terra dot_fn(a: &float, b: &float, dim: uint32) : float
    var total : float = 0.0f
    var i : uint32 = 0

    while i + 4 <= dim do
        var va = @[&vector(float, 4)](&(a[i]))
        var vb = @[&vector(float, 4)](&(b[i]))
        var prod = va * vb
        total = total + (prod[0] + prod[1] + prod[2] + prod[3])
        i = i + 4
    end

    while i < dim do
        total = total + (a[i] * b[i])
        i = i + 1
    end

    return total
end

-- Cosine distance: 1.0 - (dot(a, b) / (|a| * |b|))
local terra cosine_dist_fn(a: &float, b: &float, dim: uint32) : float
    var dot_val = dot_fn(a, b, dim)
    var norm_a = C.sqrtf(dot_fn(a, a, dim))
    var norm_b = C.sqrtf(dot_fn(b, b, dim))
    var denom = norm_a * norm_b
    if denom < 1e-9f then return 1.0f end
    var sim = dot_val / denom
    if sim > 1.0f then sim = 1.0f end
    if sim < -1.0f then sim = -1.0f end
    return 1.0f - sim
end

-- Manhattan distance (L1)
local terra l1_fn(a: &float, b: &float, dim: uint32) : float
    var total : float = 0.0f
    for i = 0, dim do
        total = total + C.fabsf(a[i] - b[i])
    end
    return total
end

dist.l2_sq = l2_sq_fn
dist.l2 = l2_fn
dist.dot = dot_fn
dist.cosine_dist = cosine_dist_fn
dist.l1 = l1_fn

return dist
