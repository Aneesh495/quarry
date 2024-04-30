#!/bin/bash
# run_benchmarks.sh
# Unified master benchmark harness for Quarry analytical database.
# Runs all performance benchmarks across JIT compilation, compression,
# hash joins, vector similarity search, and TPC-H analytical queries.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

export PATH="$HOME/.local/bin:$PATH"

BOLD='\033[1m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BOLD}=================================================================${NC}"
echo -e "${BOLD}  QUARRY PERFORMANCE BENCHMARK SUITE${NC}"
echo -e "${BOLD}=================================================================${NC}"

# 1. JIT Compilation vs Volcano Interpretation
echo -e "\n${CYAN}>>> 1. JIT Compilation Benchmark (1,000,000 Rows)${NC}"
terra benches/bench_jit_vs_interp.t

# 2. Compression Throughput & Ratios
echo -e "\n${CYAN}>>> 2. Columnar Compression Benchmark${NC}"
terra benches/bench_compression.t

# 3. Hash Join Throughput
echo -e "\n${CYAN}>>> 3. Vectorized Hash Join Benchmark (500k Keys, 1M Probes)${NC}"
terra benches/bench_joins.t

# 4. Vector k-NN Search (HNSW vs Flat SIMD)
echo -e "\n${CYAN}>>> 4. Vector k-NN Similarity Search Benchmark${NC}"
terra benches/bench_vector_knn.t

# 5. Multi-query TPC-H Suite
echo -e "\n${CYAN}>>> 5. Analytical TPC-H Query Benchmark (1,000,000 Rows)${NC}"
terra benches/bench_tpch.t

# 6. SIMD Hardware Acceleration
echo -e "\n${CYAN}>>> 6. SIMD Hardware Acceleration Benchmark (10M Floats)${NC}"
terra benches/bench_simd.t

echo -e "\n${BOLD}=================================================================${NC}"
echo -e "${BOLD}  ALL BENCHMARKS COMPLETED SUCCESSFULLY${NC}"
echo -e "${BOLD}=================================================================${NC}"
