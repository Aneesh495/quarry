# TPC-H Analytical Benchmarks & Performance Metrics

This document details the performance benchmarks of the Quarry analytical database engine across standard TPC-H analytical queries and micro-benchmarks on modern 64-bit hardware.

## Benchmark Hardware Environment

- **Architecture**: ARM64 / Apple Silicon (M-Series)
- **Vector Extensions**: 128-bit ARM NEON vector registers
- **Memory Subsystem**: L1 Data Cache (128 KB per core), L2 Cache (4 MB shared), Unified Memory
- **Compiler Infrastructure**: Terra v1.2.2 targeting LLVM 16.0
- **Allocation Strategy**: 64-byte cache line aligned chunk buffers

---

## TPC-H Analytical Query Suite (1,000,000 Rows)

The benchmark executes standard TPC-H query kernels directly on in-memory columnar tables populated with 1,000,000 tuples of lineitem and orders data.

| Query | Name / Characteristic | Time (us) | Latency (ms) | Throughput (M rows/s) |
|---|---|---|---|---|
| **Q1** | Pricing Summary Report (Multi-aggregate) | 4,046.0 | 4.05 ms | 247.16 M/s |
| **Q6** | Forecasting Revenue Change (Range scan) | 4,503.0 | 4.50 ms | 222.07 M/s |
| **Q12**| Shipping Modes & Order Priority | 3,598.0 | 3.60 ms | 277.93 M/s |
| **Q14**| Promotion Effect Query (Ratio aggregation) | 1,868.0 | 1.87 ms | 535.33 M/s |
| **Q19**| Discounted Revenue (Compound clauses) | 3,638.0 | 3.64 ms | 274.88 M/s |

### Query Details

#### Query 1: Pricing Summary Report
```sql
SELECT l_returnflag, l_linestatus,
       SUM(l_quantity) AS sum_qty,
       SUM(l_extendedprice) AS sum_base_price,
       SUM(l_extendedprice * (1 - l_discount)) AS sum_disc_price,
       SUM(l_extendedprice * (1 - l_discount) * (1 + l_tax)) AS sum_charge
FROM lineitem
GROUP BY l_returnflag, l_linestatus;
```
- Computes four concurrent arithmetic aggregations across 1,000,000 rows.
- Executes in 4.05 ms with zero intermediate memory allocations.

#### Query 6: Forecasting Revenue Change
```sql
SELECT SUM(l_extendedprice * l_discount) AS revenue
FROM lineitem
WHERE l_shipdate >= '1994-01-01' AND l_shipdate <= '1995-01-01'
  AND l_discount >= 0.05 AND l_discount <= 0.07
  AND l_quantity < 24;
```
- Multi-predicate range filter evaluated in registers with branch prediction optimization.
- Scans at 222 Million rows/second.

#### Query 14: Promotion Effect
```sql
SELECT 100.0 * SUM(CASE WHEN p_type LIKE 'PROMO%' THEN l_extendedprice * (1 - l_discount) ELSE 0 END) /
       SUM(l_extendedprice * (1 - l_discount)) AS promo_revenue
FROM lineitem, part
WHERE l_partkey = p_partkey AND l_shipdate >= '1995-09-01';
```
- Inlined branchless ternary accumulation.
- Scans at over 535 Million rows/second.

---

## JIT Compilation vs Volcano Interpretation Benchmark

Evaluates a complex filter and projection query: `(price * (100 - discount) / 100) > threshold` on 1,000,000 tuples.

| Engine Mode | Time (us) | Latency (ms) | Throughput (M rows/s) | Speedup Ratio |
|---|---|---|---|---|
| **Volcano / Interpreted** | 3,463.0 us | 3.46 ms | 288.77 M/s | 1.00x (Baseline) |
| **Quarry Fused JIT** | 1,021.0 us | 1.02 ms | 979.43 M/s | **3.39x Faster** |

---

## Columnar Compression Throughput & Ratios (100,000 Values)

Evaluates compression ratios and decompression throughput across the four core codecs.

| Codec | Raw Size (KB) | Compressed Size (KB) | Compression Ratio | Encode Time (us) | Decode Time (us) | Decode Throughput (M/s) |
|---|---|---|---|---|---|---|
| **Bitpack (5-bit)** | 390.6 KB | 61.0 KB | **6.40x** | 153.0 us | 165.0 us | **606.06 M/s** |
| **Delta-FOR** | 781.2 KB | 73.3 KB | **10.66x** | 341.0 us | 219.0 us | **456.62 M/s** |
| **RLE (Runs)** | 781.2 KB | 1.2 KB | **666.67x** | 52.0 us | 80.0 us | **1,250.00 M/s** |
| **Dictionary** | 976.6 KB | 97.9 KB | **9.97x** | 1,280.0 us | 1.0 us | **> 1,000.0 M/s** |

---

## Vector Similarity Search Benchmark (5,000 Vectors, Dim 64, k=5)

Compares exhaustive flat SIMD scanning against the HNSW graph index.

| Algorithm | Query Latency (us) | Throughput (QPS) | Relative Accuracy | Speedup Ratio |
|---|---|---|---|---|
| **Exact Flat SIMD** | 140.19 us | 7,133.2 QPS | 100.0% | 1.0x (Baseline) |
| **HNSW Proximity Graph** | 2.36 us | 423,728.8 QPS | 97.9% | **59.4x Faster** |

---

## SIMD Hardware Acceleration Microbenchmark (10,000,000 Floats)

Measures raw compute performance comparing scalar loops to 4-wide SIMD vector intrinsics.

| Kernel | Scalar Time (us) | SIMD Time (us) | SIMD Throughput (GFLOPS) | Speedup Ratio |
|---|---|---|---|---|
| **Dot Product** | 22,165.0 us | 6,046.0 us | 3.31 GFLOPS | **3.67x Faster** |
| **L2 Distance** | 13,802.0 us | 3,867.0 us | 7.76 GFLOPS | **3.57x Faster** |
