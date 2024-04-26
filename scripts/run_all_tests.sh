#!/bin/bash
# run_all_tests.sh
# Unified master test runner for Quarry analytical database.
# Executes all test suites across Terra, C ABI, Python SDK, and CLI scripts.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

export PATH="$HOME/.local/bin:$PATH"

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}=================================================================${NC}"
echo -e "${BOLD}  QUARRY MASTER VERIFICATION SUITE${NC}"
echo -e "${BOLD}=================================================================${NC}"

PASSED_COUNT=0
TOTAL_COUNT=0

run_test() {
    local cmd="$1"
    local desc="$2"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    echo -e "\n--> Running Test ${TOTAL_COUNT}: ${desc}"
    if eval "$cmd"; then
        echo -e "${GREEN}[PASS] ${desc}${NC}"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo -e "${RED}[FAIL] ${desc}${NC}"
        exit 1
    fi
}

# 1. Em Dash Verification
run_test "python3 verify_no_em_dashes.py" "Strict Em Dash and En Dash Audit"

# 2. Core Terra Test Suites
run_test "terra tests/test_common.t" "Common (Alloc, Bits, Hash, SIMD, Status, Timer)"
run_test "terra tests/test_types.t" "Types (DataType, Value, DenseVector)"
run_test "terra tests/test_storage.t" "Storage (ValidityMask, ColumnVector, DataChunk, Table, Catalog)"
run_test "terra tests/test_compression.t" "Compression (Bitpack, Delta-FOR, RLE, Dict, Codec)"
run_test "terra tests/test_parser.t" "SQL Parser & Pratt Precedence Lexer"
run_test "terra tests/test_optimizer.t" "Logical Planner, Constant Folding, Pushdown & Physical Plan"
run_test "terra tests/test_execution.t" "Morsel Queue, Thread Pool & Execution Context"
run_test "terra tests/test_operators.t" "Physical Operators (Scan, Filter, Project, Limit, Window)"
run_test "terra tests/test_joins.t" "Physical Hash Join (Inner & Left Outer)"
run_test "terra tests/test_aggregates.t" "Hash Group-by & Global Aggregations"
run_test "terra tests/test_sort.t" "In-place Columnar Sort"
run_test "terra tests/test_jit_codegen.t" "Multi-stage JIT Code Generation & Kernel Cache"
run_test "terra tests/test_vector_index.t" "SIMD Distances, HNSW Graph, IVF & Hybrid Queries"
run_test "terra tests/test_vector_knn_op.t" "PhysicalVectorKNN Pipeline Breaker Operator"
run_test "terra tests/test_io.t" "Binary Serializer, CSV & Apache Arrow Bridge"
run_test "terra tests/test_tpch.t" "TPC-H Q1 & Q6 Analytical Verification"
run_test "terra tests/test_regressions.t" "Regression & Bug Reproduction Suite"
run_test "terra tests/test_concurrency.t" "Multi-Threaded Morsel Contention Stress Test"
run_test "terra tests/test_null_handling.t" "SQL Three-Valued Logic & Null Bitmap Remainder Handling"
run_test "terra tests/test_nested_queries.t" "Complex Nested SQL AST & Operator Precedence"
run_test "terra tests/test_simd_accuracy.t" "SIMD Numerical Stability & Non-Power-of-2 Tail Handling"
run_test "terra tests/test_codec_roundtrip.t" "Exhaustive Compression Codec Roundtrip"
run_test "terra tests/test_arrow_roundtrip.t" "Apache Arrow C Data Interface Zero-Copy Roundtrip"

# 3. Native C Integration Test
run_test "clang -O3 -Iinclude tests/test_c_api.c -Llib -lquarry -o tests/test_c_api_bin && ./tests/test_c_api_bin" "Native C Foreign Function Interface Integration"

# 4. Python SDK Test Suites
run_test "PYTHONPATH=\"python:\$PYTHONPATH\" python3 python/tests/test_pyquarry.py" "Python PyQuarry SDK & DataFrame Integration"
run_test "PYTHONPATH=\"python:\$PYTHONPATH\" python3 tests/test_http_server.py" "Embedded HTTP REST API Daemon Router"

# 5. CLI Launcher Integration Test
run_test "./tests/test_cli_runner.sh" "Command Line Interface Launcher & Argument Parser"

echo -e "\n${BOLD}=================================================================${NC}"
echo -e "${GREEN}${BOLD}ALL ${PASSED_COUNT}/${TOTAL_COUNT} TEST SUITES PASSED FLAWLESSLY!${NC}"
echo -e "${BOLD}=================================================================${NC}"
