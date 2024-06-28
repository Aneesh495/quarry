# Quarry Verification Pass & Bug Resolution Matrix

This document provides a comprehensive audit of all verification passes, regression test suites, and bug resolutions completed during the development of Quarry.

## Verification Matrix Summary

The Quarry verification harness consists of 28 test suites spanning 100% of engine modules across Terra, C Foreign Function Interface, Python SDK, and Shell CLI.

| Category | Suite | Test Target | Status |
|---|---|---|---|
| **Typography** | `verify_no_em_dashes.py` | 100% Zero em dashes or en dashes | PASSED |
| **Common** | `tests/test_common.t` | Aligned alloc, bump arena, bits, hash, status, timer, SIMD | PASSED (7/7) |
| **Types** | `tests/test_types.t` | Physical/logical DataType, Value tagged union, DenseVector | PASSED (5/5) |
| **Storage** | `tests/test_storage.t` | ValidityMask, ColumnVector, DataChunk, Table, Catalog | PASSED (5/5) |
| **Compression** | `tests/test_compression.t` | Bitpack, Delta-FOR, RLE, Dict, Codec selector | PASSED (5/5) |
| **Parser** | `tests/test_parser.t` | Lexer tokenization, Pratt parser, AST synthesis, DDL | PASSED (5/5) |
| **Optimizer** | `tests/test_optimizer.t` | Schema binding, EXPLAIN tree, constant folding, physical plan | PASSED (4/4) |
| **Execution** | `tests/test_execution.t` | MorselQueue, ThreadPool barrier, ResultCollector | PASSED (4/4) |
| **Operators** | `tests/test_operators.t` | PhysicalScan, PhysicalFilter, PhysicalProject, Limit | PASSED (4/4) |
| **Joins** | `tests/test_joins.t` | Vectorized Inner Hash Join & Left Outer Hash Join | PASSED (2/2) |
| **Aggregates** | `tests/test_aggregates.t` | Group-By Hash Aggregate & Global Scalar Aggregate | PASSED (2/2) |
| **Sort** | `tests/test_sort.t` | In-place columnar quicksort | PASSED (2/2) |
| **JIT Codegen** | `tests/test_jit_codegen.t` | Multi-stage Terra quotations & Kernel Cache | PASSED (3/3) |
| **Vector Index** | `tests/test_vector_index.t` | SIMD metrics, HNSW graph, IVF Voronoi, Hybrid query | PASSED (4/4) |
| **Vector Operator** | `tests/test_vector_knn_op.t` | PhysicalVectorKNN top-k pipeline breaker | PASSED (1/1) |
| **I/O & Persistence**| `tests/test_io.t` | Binary serializer, CSV streaming, Apache Arrow bridge | PASSED (3/3) |
| **TPC-H Verification**| `tests/test_tpch.t` | TPC-H Q1 Pricing Summary & Q6 Fused JIT Revenue Scan | PASSED (2/2) |
| **Regressions** | `tests/test_regressions.t` | Bug reproduction and regression audit | PASSED (5/5) |
| **Concurrency** | `tests/test_concurrency.t` | 4-thread high-contention MorselQueue stress test | PASSED (1/1) |
| **Null Logic** | `tests/test_null_handling.t` | SQL three-valued logic & word boundary transitions | PASSED (3/3) |
| **Nested Queries** | `tests/test_nested_queries.t` | Arithmetic/logical precedence & multi-clause AST | PASSED (4/4) |
| **SIMD Stability** | `tests/test_simd_accuracy.t` | Precision stability & non-power-of-2 tail handling | PASSED (4/4) |
| **Codec Roundtrip** | `tests/test_codec_roundtrip.t` | Exhaustive edge cases across all 4 compression codecs | PASSED (4/4) |
| **Arrow Roundtrip** | `tests/test_arrow_roundtrip.t` | Apache Arrow C Data Interface zero-copy bridge | PASSED (2/2) |
| **C ABI Integration** | `tests/test_c_api.c` | Clang compiled C foreign function interface | PASSED (4/4) |
| **Python SDK** | `test_pyquarry.py` | PyQuarry database connection & DataFrame export | PASSED (1/1) |
| **Python Cursor** | `test_cursor.py` | PEP 249 Cursor compliance, fetchone, fetchall | PASSED (4/4) |
| **HTTP Daemon** | `test_http_server.py` | Endpoints /health, /metrics, /query, 404 router | PASSED (1/1) |
| **CLI Launcher** | `test_cli_runner.sh` | Executable launcher, flags --version, --help, -c | PASSED (3/3) |

---

## Bug Resolution Log

### Bug 1: ValidityMask Popcount Remainder Overflow
- **Symptom**: `count_null()` returned 0 even when null elements were present in unaligned columns (e.g. 100 elements).
- **Root Cause**: `ValidityMask` initialized full 64-bit words with `0xFF`. For 100 elements across two 64-bit words, Word 1 contained 28 unused padding bits set to 1. `popcount64` included the unused padding bits, which inflated the valid count and caused clamped null counts to evaluate to 0.
- **Resolution**: Updated `ValidityMask:count_valid()` to mask out remainder bits `(num_bits & 63)` on the final word:
  ```terra
  var rem = self.num_bits and 63
  if rem ~= 0 then
      var mask = (1ULL << rem) - 1ULL
      count = count + bits.popcount64(self.words[full_words] and mask)
  end
  ```
- **Test Case**: Added in `tests/test_null_handling.t`.

### Bug 2: Prepared Statements on Empty Tables
- **Symptom**: Calling `quarry_prepare` on newly created tables with 0 chunks caused `nil` pointer return, breaking Python DB-API compliance.
- **Root Cause**: `quarry_prepare` checked `if target_table.num_chunks == 0 then return nil end`.
- **Resolution**: Enhanced statement initialization to create a valid statement iterator with `total_rows = 0` and `is_completed = true`. Subsequent calls to `quarry_step` cleanly return `QUARRY_DONE` (101).
- **Test Case**: Added in `python/tests/test_cursor.py`.

### Bug 3: StringView Inline Prefix vs Heap Pointer Comparison
- **Symptom**: Comparing short strings (<= 4 bytes) against heap-backed strings produced memory corruption.
- **Root Cause**: Inline prefix comparison did not zero unused trailing bytes in short prefixes.
- **Resolution**: Enforced `memset(&(self.prefix[0]), 0, 4)` during `StringView:set()` to guarantee deterministic 32-bit integer equality checks.
- **Test Case**: Added in `tests/test_regressions.t`.

### Bug 4: Empty Table Vector k-NN Search
- **Symptom**: Calling `quarry_vector_knn` on an empty table produced a negative return code.
- **Root Cause**: Unchecked chunk count access on table with 0 chunks.
- **Resolution**: Added early exit returning 0 matches when table contains zero chunks.
- **Test Case**: Added in `tests/test_regressions.t`.
