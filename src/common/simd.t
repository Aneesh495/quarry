-- Quarry SIMD vector abstraction subsystem
-- Exploits LLVM vector intrinsics and hardware vector lanes for analytical math.

local C = require("src.common.c").C

local simd = {}

simd.VEC4F = vector(float, 4)
simd.VEC8F = vector(float, 8)
simd.VEC4D = vector(double, 4)

-- Vectorized dot product for 4-wide float vector
terra simd.dot4f(a: &float, b: &float) : float
    var va = @[&vector(float, 4)](a)
    var vb = @[&vector(float, 4)](b)
    var prod = va * vb
    return prod[0] + prod[1] + prod[2] + prod[3]
end

-- Vectorized sum for 4-wide float vector
terra simd.sum4f(a: &float) : float
    var va = @[&vector(float, 4)](a)
    return va[0] + va[1] + va[2] + va[3]
end

-- Vectorized L2 squared distance between 4-element arrays
terra simd.l2_sq4f(a: &float, b: &float) : float
    var va = @[&vector(float, 4)](a)
    var vb = @[&vector(float, 4)](b)
    var diff = va - vb
    var sq = diff * diff
    return sq[0] + sq[1] + sq[2] + sq[3]
end

-- Vectorized sum of floats across length N using 4-wide unrolling
terra simd.sum_array_f32(arr: &float, n: C.size_t) : float
    var total : float = 0.0f
    var i : C.size_t = 0
    var acc = vector(0.0f, 0.0f, 0.0f, 0.0f)

    while i + 4 <= n do
        var v = @[&vector(float, 4)](&(arr[i]))
        acc = acc + v
        i = i + 4
    end

    total = acc[0] + acc[1] + acc[2] + acc[3]

    -- Scalar cleanup tail
    while i < n do
        total = total + arr[i]
        i = i + 1
    end

    return total
end

-- Vectorized dot product of two float arrays of length N
terra simd.dot_product_f32(a: &float, b: &float, n: C.size_t) : float
    var total : float = 0.0f
    var i : C.size_t = 0
    var acc = vector(0.0f, 0.0f, 0.0f, 0.0f)

    while i + 4 <= n do
        var va = @[&vector(float, 4)](&(a[i]))
        var vb = @[&vector(float, 4)](&(b[i]))
        acc = acc + (va * vb)
        i = i + 4
    end

    total = acc[0] + acc[1] + acc[2] + acc[3]

    while i < n do
        total = total + (a[i] * b[i])
        i = i + 1
    end

    return total
end

return simd
