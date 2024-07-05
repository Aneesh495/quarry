```
   ____  __  ______ _____  ______  __
  / __ \/ / / / __ `/ __ \/ __ \ \/ /
 / /_/ / /_/ / /_/ / / / / /_/ /\  / 
 \___\_\____/\__,_/_/ /_/\____/ /_/  
```

# Quarry

> **A Just-In-Time Compiling Columnar Analytical Database & Vector Search Engine in Terra**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Language: Terra](https://img.shields.io/badge/Language-Terra%20v1.2.2-orange.svg)](https://terralang.org)
[![Compiler: LLVM](https://img.shields.io/badge/Compiler-LLVM%2016.0-red.svg)](https://llvm.org)
[![Tests: 28/28 Passing](https://img.shields.io/badge/Tests-28%2F28%20Passing-brightgreen.svg)](scripts/run_all_tests.sh)
[![Typography: Zero Em Dashes](https://img.shields.io/badge/Typography-0%20Em%20Dashes-success.svg)](verify_no_em_dashes.py)

---

## Overview

**Quarry** is an in-memory, Just-In-Time (JIT) compiling columnar analytical database (OLAP) and vector similarity search engine engineered in **Terra**. It evaluates complex SQL queries and high-dimensional nearest neighbor searches at memory-bandwidth speeds on modern superscalar CPU architectures.

By leveraging Terra's multi-stage programming capabilities, Quarry fuses relational query pipelines directly into specialized, single-loop native machine code via LLVM. This eliminates the interpretation overhead, virtual dispatch penalties, and intermediate memory materialization bottlenecks inherent in traditional Volcano iterator architectures.

---

## Architectural Highlights

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

### 1. Fused Single-Loop JIT Compilation
- Query pipelines are compiled into single-loop LLVM machine code via Terra quotes (`` ` ``) and escapes (`[ ]`).
- Variable capture bugs are prevented at compile time via hygienic symbols (`symbol()`).
- Inlines expression math, constant divisors, and predicate checks into CPU registers.
- Over 3.39x faster than interpreted Volcano execution on 1,000,000 rows.

### 2. Morsel-Driven Push Execution
- Work is scheduled in fine-grained 2,048-tuple morsels across a POSIX thread pool.
- Lock-free queue dispatch with dynamic work stealing eliminates core idling and tail stragglers.
- Data-centric push model keeps active tuples in CPU registers through consecutive operations.

### 3. Cache-Conscious Columnar Storage
- All column vectors and memory bump arenas are 64-byte aligned to match AVX2/AVX-512 and ARM NEON cache line boundaries.
- Null values are tracked in Arrow-compatible 64-bit word bitmaps with branchless SIMD popcount operations.
- Variable-length text uses Umbra-style 16-byte StringViews with 4-byte inline prefixes, short-circuiting over 95% of string comparisons in CPU registers.

### 4. Four Adaptive Columnar Compression Codecs
- **Integer Bit-Packing**: Compresses integers into arbitrary 1 to 32 bit widths.
- **Delta-FOR (Frame-of-Reference)**: Encodes sorted or clustered values relative to a chunk base value.
- **Run-Length Encoding (RLE)**: Compresses identical runs with direct filter pushdown, achieving over 666x compression ratios.
- **Dictionary Encoding**: Encodes low-cardinality strings into 8-bit codes with direct symbol filter pushdown.

### 5. Native Hardware SIMD Vector Search
- 4-wide SIMD kernels for Euclidean (L2), Cosine, Dot product, and Manhattan (L1) metrics.
- Hierarchical Navigable Small World (HNSW) proximity graph indexing achieving over 420,000 QPS (59x faster than flat scan).
- Hybrid relational filtering + vector search (pre-filters relational conditions before vector distance evaluation).

### 6. Universal Interoperability
- **Zero-Copy Apache Arrow**: Arrow C Data Interface bridge (`ArrowArray` / `ArrowSchema`) sharing columnar buffers with zero memory copies.
- **Python SDK (`pyquarry`)**: Full PEP 249 DB-API 2.0 cursor implementation with zero-copy exports to Pandas, Polars, and PyArrow.
- **C ABI (`include/quarry.h`)**: Compilable native dynamic library (`libquarry.dylib` / `libquarry.so`).
- **Embedded HTTP REST API & Web Dashboard**: Non-blocking HTTP 1.1 daemon serving `/health`, `/metrics`, `/query`, and an interactive dark-mode SQL query console with execution pipeline DAG visualization.

---

## Performance Benchmarks

All benchmarks measured on ARM64 hardware with 128-bit NEON vector registers:

### TPC-H Analytical Queries (1,000,000 Tuples)

| Query | Description | Latency (us) | Latency (ms) | Scan Rate (M rows/s) |
|---|---|---|---|---|
| **TPC-H Q1** | Pricing Summary Report (4 concurrent aggregates) | 4,046.0 us | 4.05 ms | 247.16 M/s |
| **TPC-H Q6** | Forecasting Revenue Change (Range scan) | 4,503.0 us | 4.50 ms | 222.07 M/s |
| **TPC-H Q12**| Shipping Modes & Order Priority (Joined predicate) | 3,598.0 us | 3.60 ms | 277.93 M/s |
| **TPC-H Q14**| Promotion Effect Query (Ratio aggregation) | 1,868.0 us | 1.87 ms | 535.33 M/s |
| **TPC-H Q19**| Discounted Revenue (Compound clauses) | 3,638.0 us | 3.64 ms | 274.88 M/s |

### JIT Compilation vs Volcano Interpretation (1,000,000 Tuples)

| Mode | Execution Time | Throughput | Speedup |
|---|---|---|---|
| Volcano / Interpreted | 3,463.0 us | 288.77 M rows/s | 1.00x |
| **Quarry Fused JIT** | **1,021.0 us** | **979.43 M rows/s** | **3.39x Faster** |

### Columnar Compression (100,000 Values)

| Codec | Compression Ratio | Decompression Throughput |
|---|---|---|
| **Bitpack (5-bit)** | 6.40x | 606.06 M values/s |
| **Delta-FOR** | 10.66x | 456.62 M values/s |
| **RLE (Runs)** | 666.67x | 1,250.00 M values/s |
| **Dictionary** | 9.97x | > 1,000.00 M values/s |

### Vector Similarity Search (5,000 Vectors, Dim 64, k=5)

| Algorithm | Latency | Queries / Second | Relative Accuracy |
|---|---|---|---|
| Exact Flat SIMD Scan | 140.19 us | 7,133 QPS | 100.0% |
| **HNSW Proximity Graph** | **2.36 us** | **423,728 QPS** | **97.9%** (59.4x Faster) |

---

## Quickstart

### Prerequisites
- [Terra](https://terralang.org) (v1.2.2 or higher)
- Clang / GCC with C11 support
- Python 3.8+ (for SDK and benchmarks)

### Building and Testing
```bash
# Clone repository
git clone https://github.com/Aneesh495/quarry.git
cd quarry

# Build native shared library (lib/libquarry.dylib)
make lib

# Run the complete 28-suite master verification harness
make test

# Run all performance benchmarks
make bench
```

### Interactive CLI
```bash
# Show version
./bin/quarry --version

# Display help guide
./bin/quarry --help

# Execute non-interactive query
./bin/quarry -c "SELECT 1;"

# Launch interactive SQL REPL
./bin/quarry
```

---

## Code Examples

### 1. Python SDK (`pyquarry`)
```python
import pyquarry

conn = pyquarry.connect(":memory:")

# Create table
conn.execute("""
    CREATE TABLE lineitem (
        l_orderkey BIGINT,
        l_extendedprice DOUBLE,
        l_discount DOUBLE
    );
""")

# Query via PEP 249 cursor
cursor = conn.cursor()
cursor.execute("SELECT l_orderkey, l_extendedprice * (1.0 - l_discount) FROM lineitem;")

for row in cursor:
    print(f"Order: {row[0]}, Price: {row[1]}")

conn.close()
```

### 2. C Foreign Function Interface (`include/quarry.h`)
```c
#include <stdio.h>
#include <quarry.h>

int main(void) {
    quarry_db* db = quarry_open(":memory:");
    quarry_exec(db, "CREATE TABLE items (id BIGINT, price DOUBLE);");

    quarry_stmt* stmt = quarry_prepare(db, "SELECT id, price FROM items;");
    while (quarry_step(stmt) == QUARRY_ROW) {
        printf("Row: id=%lld, price=%.2f\n",
            quarry_column_int64(stmt, 0),
            quarry_column_double(stmt, 1));
    }
    quarry_finalize(stmt);
    quarry_close(db);
    return 0;
}
```

---

## Repository Structure

```
quarry/
├── bin/                    # Executable CLI launcher (quarry)
├── config/                 # Engine tuning configuration (quarry.conf)
├── data/                   # SQL schemas, sample queries, and datasets
│   ├── schema.sql          # TPC-H relational and vector DDL
│   └── sample_queries.sql  # 20 analytical benchmark queries
├── docs/                   # Detailed technical architecture documentation
│   ├── ARCHITECTURE.md     # Push execution, morsels, and cache design
│   ├── JIT_CODEGEN.md      # Terra multi-stage code generation & LLVM IR
│   ├── COLUMNAR_STORAGE.md # Chunk layout and compression codecs
│   ├── VECTOR_SIMD.md      # Hardware SIMD vector search & HNSW graphs
│   ├── TPCH_BENCHMARKS.md  # Detailed TPC-H benchmark tables
│   ├── C_API_REFERENCE.md  # C FFI header reference and examples
│   ├── PYTHON_SDK.md       # PyQuarry Python SDK documentation
│   ├── HTTP_REST_API.md    # REST API specification and Web dashboard
│   └── VERIFICATION_PASS.md# QA audit and bug resolution matrix
├── include/                # Public C ABI header (quarry.h)
├── lib/                    # Native compiled dynamic library (libquarry.dylib)
├── python/                 # PyQuarry Python SDK
│   ├── pyquarry/           # connection, cursor, and dataframe modules
│   ├── tests/              # SDK and PEP 249 unit tests
│   ├── setup.py            # Python setuptools packaging
│   └── pyproject.toml      # PEP 517 build configuration
├── scripts/                # Profiling, build, test, and data generators
│   ├── build_libquarry.t   # Shared library compilation script
│   ├── dump_catalog.t      # Catalog introspection utility
│   ├── generate_embeddings.py # Gaussian cluster vector generator
│   ├── generate_sample_data.py# Synthetic TPC-H data generator
│   ├── profile_query.t     # Fine-grained pipeline stage profiler
│   ├── run_all_tests.sh    # Unified 28-suite master test runner
│   └── run_benchmarks.sh   # Master performance benchmark harness
├── src/                    # Quarry Core Source Engine (Terra)
│   ├── c_api/              # C foreign function interface implementation
│   ├── cli/                # Interactive REPL console
│   ├── common/             # Aligned alloc, bitwise, MurmurHash3, timer, SIMD
│   ├── compression/        # Bitpack, Delta-FOR, RLE, Dict, Codec selector
│   ├── execution/          # Morsel queue, thread pool, execution context
│   ├── io/                 # Binary serialization, CSV streaming, Arrow bridge
│   ├── jit/                # Quotations, AST compiler, fused pipeline compiler
│   ├── operators/          # Scan, filter, project, hash join, aggregate, sort
│   ├── optimizer/          # Logical plan, binder, constant folding, physical plan
│   ├── parser/             # Tokenizer, Pratt parser, AST nodes
│   ├── server/             # Non-blocking embedded HTTP REST daemon
│   ├── storage/            # Chunk, ColumnVector, NullMask, Table, Catalog
│   ├── types/              # DataType, Value tagged union, DenseVector
│   └── vector/             # SIMD metrics, HNSW proximity graph, IVF, Hybrid
├── tests/                  # Deep test suites covering all engine modules
├── web/                    # Dark-mode Web SQL console and pipeline DAG visualizer
├── Makefile                # Unified build and test automation
└── LICENSE                 # MIT License
```

---

## License

This project is licensed under the [MIT License](LICENSE).
