# Quarry Architecture

Quarry is an in-memory, Just-In-Time (JIT) compiling columnar analytical database (OLAP) and vector search engine engineered in Terra. It is designed from first principles to maximize hardware efficiency on modern superscalar CPU architectures through data-centric push-based pipeline execution, cache-conscious columnar layouts, adaptive bit-level compression, and LLVM-backed query compilation.

```
+-----------------------------------------------------------------------------+
|                                SQL Query                                    |
|                                    |                                        |
|                                    v                                        |
|                        Pratt Expression Parser                              |
|                                    |                                        |
|                                    v                                        |
|                          Logical Query Plan                                 |
|                                    |                                        |
|                                    v                                        |
|                    Rule-Based Query Optimizer                               |
|              (Predicate Pushdown, Constant Folding)                         |
|                                    |                                        |
|                                    v                                        |
|                         Physical Pipeline Plan                              |
|                                    |                                        |
|                   +----------------+----------------+                       |
|                   |                                 |                       |
|                   v                                 v                       |
|       Terra JIT Compiler                  Morsel Dispatcher                 |
|    (Single-Loop Kernel Fusion)           (Parallel Work Stealing)           |
|                   |                                 |                       |
|                   +----------------+----------------+                       |
|                                    |                                        |
|                                    v                                        |
|                       Vectorized Push Execution                             |
|          +-------------------------------------------------------+          |
|          | Columnar Storage Engine:                              |          |
|          | - 64-Byte Cache Line Aligned Contiguous Buffers       |          |
|          | - Arrow-Compatible 64-Bit Validity Masks              |          |
|          | - German / Umbra Style 16-Byte Prefix String Views   |          |
|          | - Adaptive Codecs: Bitpack, Delta-FOR, RLE, Dict      |          |
|          | - Hardware SIMD Accelerated Vector Search (HNSW / IVF)|          |
|          +-------------------------------------------------------+          |
+-----------------------------------------------------------------------------+
```

## Core Architectural Pillars

### 1. Push-Based Pipeline Execution

Traditional analytical database engines rely on the Volcano iterator model, where each relational operator exposes a `next()` virtual method. In this pull-based model, each tuple (or block of tuples) incurs multiple virtual function calls, destroying branch prediction buffers and evicting data from L1/L2 instruction caches.

Quarry implements data-centric push-based execution (Neumann, 2011). Instead of child operators waiting for parent operators to pull data, parent operators define compiled sinks that consume tuples pushed up from the storage layers:

1. Data is loaded from memory into CPU registers once.
2. The entire pipeline of operators (scans, projections, filters, math operations) processes the tuple in registers without materializing intermediate data in memory buffers.
3. The tuple is pushed directly into a pipeline breaker (e.g., hash join build table, aggregate hash map, sort buffer, or top-k vector accumulator).

### 2. Morsel-Driven Parallelism

Quarry partitions table scans into fine-grained execution quantum units called "morsels" (Leis et al., 2014):

- Each morsel represents a chunk of 2,048 contiguous tuples.
- Worker threads from a shared POSIX thread pool dynamically claim morsels from a central lock-free queue using atomic fetch-and-add operations.
- Dynamic morsel stealing ensures optimal load balancing across CPU cores, eliminating tail-latency stragglers caused by uneven filter selectivity or core frequency throttling.

### 3. Pipeline Breakers and Materialization Boundaries

Pipelines in Quarry are strictly bounded by pipeline breakers:

- **Scan / Filter / Project**: Non-breaking streaming pipeline. Operates in single-loop fused machine code.
- **PhysicalHashJoin**:
  - *Build Phase*: Consumes the right-side relation and populates an open-addressing hash table with MurmurHash3 key mixing. Pipeline breaker.
  - *Probe Phase*: Consumes the left-side stream, probes the hash table in registers, and pushes matched rows downstream.
- **PhysicalAggregate**:
  - *Scalar Aggregation*: Accumulates running sums, counts, and extrema in CPU registers. Emits a single tuple at completion.
  - *Hash Group-By*: Accumulates grouped aggregates into a linear-probing hash table.
- **PhysicalVectorKNN**:
  - Top-K pipeline breaker. Computes SIMD vector distances against candidate embeddings and maintains a bounded sorted array of the top-k nearest neighbors. Emits the final sorted result chunk upon pipeline completion.

### 4. Cache-Conscious Columnar Layout

Memory bandwidth is the primary bottleneck in modern in-memory data processing. Quarry maximizes cache efficiency through:

- **64-Byte Boundary Alignment**: All columnar vectors and bump arenas are allocated using `posix_memalign` aligned to 64 bytes. This prevents split-cache-line loads on AVX-512, AVX2, and ARM NEON hardware.
- **Arrow-Compatible Validity Masks**: Null values are represented as compact 64-bit word bitmaps. Valid bits are marked as 1, nulls as 0. This enables SIMD bitwise popcount operations (`popcount64`) to calculate non-null row counts without branching.
- **German / Umbra String Views**: Variable-length strings use a compact 16-byte structure:
  - 4 bytes length
  - 4 bytes inline prefix
  - 8 bytes heap pointer
  Strings up to 4 bytes require zero pointer indirection. Strings longer than 4 bytes can reject equality checks in a single 32-bit register comparison against the prefix.

### 5. Multi-Stage Metaprogramming with Terra

Quarry uses Terra as its primary language. Terra integrates Lua as a compile-time metaprogramming host language while emitting native machine code via LLVM. This gives Quarry capabilities that are difficult to achieve in C, C++, or Rust:

- Relational algebra trees are analyzed at compile-time by Lua host logic.
- Type-specialized LLVM IR loops are synthesized via Terra quotes (`` ` ``) and escape operators (`[ ]`).
- No virtual dispatch, no runtime type switches, and no interpretive overhead in inner execution loops.
