-- Quarry SIMD vector abstraction subsystem
-- Exploits LLVM vector intrinsics and hardware vector lanes for analytical math.

local C = require("src.common.c").C
local size_t = C.size_t

local simd = {}

simd.VEC4F = vector(float, 4)
simd.VEC8F = vector(float, 8)
simd.VEC4D = vector(double, 4)

local terra dot4f_fn(a: &float, b: &float) : float
    var va = @[&vector(float, 4)](a)
    var vb = @[&vector(float, 4)](b)
    var prod = va * vb
    return prod[0] + prod[1] + prod[2] + prod[3]
end

local terra sum4f_fn(a: &float) : float
    var va = @[&vector(float, 4)](a)
    return va[0] + va[1] + va[2] + va[3]
end

local terra l2_sq4f_fn(a: &float, b: &float) : float
    var va = @[&vector(float, 4)](a)
    var vb = @[&vector(float, 4)](b)
    var diff = va - vb
    var sq = diff * diff
    return sq[0] + sq[1] + sq[2] + sq[3]
end

local terra sum_array_f32_fn(arr: &float, n: size_t) : float
    var total : float = 0.0f
    var i : size_t = 0
    var acc = vector(0.0f, 0.0f, 0.0f, 0.0f)

    while i + 4 <= n do
        var v = @[&vector(float, 4)](&(arr[i]))
        acc = acc + v
        i = i + 4
    end

    total = acc[0] + acc[1] + acc[2] + acc[3]

    while i < n do
        total = total + arr[i]
        i = i + 1
    end

    return total
end

local terra dot_product_f32_fn(a: &float, b: &float, n: size_t) : float
    var total : float = 0.0f
    var i : size_t = 0
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

simd.dot4f = dot4f_fn
simd.sum4f = sum4f_fn
simd.l2_sq4f = l2_sq4f_fn
simd.sum_array_f32 = sum_array_f32_fn
simd.dot_product_f32 = dot_product_f32_fn

return simd
