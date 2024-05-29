# Just-In-Time (JIT) Query Compilation & Code Generation

Quarry achieves sub-millisecond query execution through dynamic Just-In-Time (JIT) compilation using Terra's multi-stage programming capabilities. Instead of evaluating queries via interpretive tree walks or virtual function dispatch, Quarry translates validated physical query plans directly into native machine code via LLVM.

## Multi-Stage Metaprogramming in Terra

Terra is a statically-typed, low-level language embedded within the Lua runtime. It provides first-class support for multi-stage programming:

1. **Host Stage (Lua)**: Dynamic metaprogramming environment. Reads SQL ASTs, performs catalog schema resolution, evaluates cost models, and coordinates loop construction.
2. **Target Stage (Terra / LLVM)**: Statically typed native code. Compiled on-the-fly to machine instructions with register allocation, auto-vectorization, and dead-code elimination.

### Core Metaprogramming Constructs

- **Terra Quotes (`` ` ``)**: Quote expressions create code templates that are evaluated at code generation time rather than execution time.
- **Terra Escapes (`[ ]`)**: Escape expressions splice host Lua variables and symbols into Terra quotes.
- **Hygienic Symbols (`symbol(type)`)**: Generate unique, unforgeable variable references preventing variable capture bugs across complex nested subexpressions.

```lua
-- Example: Hygienic Expression Quotation in Quarry JIT Compiler
local sym_price = symbol(int64, "price")
local sym_discount = symbol(int64, "discount")

-- Generates native quote: (price * (100 - discount)) / 100
local expr_quote = `([sym_price] * (100 - [sym_discount])) / 100
```

## Single-Loop Pipeline Fusion

Traditional database engines suffer from the "materialization penalty": each operator reads an input vector from memory, evaluates a predicate or projection, and writes an output vector back to memory:

```
[Scan] ---> [Memory Buffer 1] ---> [Filter] ---> [Memory Buffer 2] ---> [Project] ---> [Memory Buffer 3]
```

In Quarry, the pipeline compiler fuses consecutive non-breaking operators into a single tight loop:

```
                      +---------------------------------------+
                      | Single Fused LLVM Inner Loop          |
[Memory Buffer] ----->|   1. Load row to CPU register         |-----> [Pipeline Breaker]
                      |   2. Inlined filter predicate check   |       (Hash Table / Heap)
                      |   3. Inlined expression math          |
                      +---------------------------------------+
```

### Generated Code Comparison

Consider the analytical query:
```sql
SELECT l_orderkey, (l_extendedprice * (100 - l_discount)) / 100
FROM lineitem
WHERE l_quantity > 24 AND l_discount < 5;
```

#### Interpreted / Volcano Overhead
- Virtual function call per tuple for `Filter.next()`
- Virtual function call per tuple for `Project.next()`
- Dynamic type switches to unpack tagged union values
- Intermediate allocation of selection vectors and projected tuples

#### Quarry Fused JIT Assembly Output
```c
// Conceptual representation of the LLVM IR emitted by Quarry:
void query_kernel(int64_t* col_qty, int64_t* col_price, int64_t* col_disc,
                  int64_t* col_key, uint32_t count, ResultSink* sink) {
    for (uint32_t i = 0; i < count; ++i) {
        int64_t q = col_qty[i];
        int64_t d = col_disc[i];
        // Branch predictor friendly inlined condition
        if (q > 24 && d < 5) {
            int64_t rev = (col_price[i] * (100 - d)) / 100;
            sink_append(sink, col_key[i], rev);
        }
    }
}
```

Because the entire loop is visible to LLVM:
- Constant divisors (`100`) are replaced with multiplication by reciprocal and bit shifts.
- Memory loads are hoisted into CPU registers.
- Consecutive integer operations are vectorized using SIMD instructions where applicable.

## Native Kernel Cache Architecture

Compiling native code incurs LLVM optimization latency (typically 50 to 500 microseconds). For repeated parameterized queries or high-throughput OLTP/hybrid workloads, compiling on every invocation would create an unacceptable bottleneck.

Quarry implements an LRU Native Kernel Cache (`KernelCache`):

1. **Cache Key**: 64-bit MurmurHash3 digest of the normalized query AST, including:
   - Operator tree topology
   - Physical column indices and data types
   - Predicate constants and comparison operators
2. **Lookup**: O(1) probe into the kernel cache hash table.
3. **Hit Path**: If a matching compiled kernel exists, Quarry retrieves the native function pointer directly and executes it with zero compilation latency.
4. **Miss Path**: The pipeline compiler generates the Terra quote, invokes LLVM to compile the native function pointer, and inserts it into the cache with LRU eviction.
