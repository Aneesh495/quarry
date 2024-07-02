# Contributing to Quarry

Thank you for your interest in contributing to Quarry! Quarry is an open-source, high-performance columnar analytical database and vector search engine written in Terra.

## Development Setup

### Prerequisites
- **Terra**: Version 1.2.2 or later installed (available at `terralang.org`)
- **LLVM**: LLVM 13.0 to 16.0
- **Clang / GCC**: C11 compliant compiler
- **Python**: Python 3.8+ for client SDK, tests, and dataset generators

### Building From Source
```bash
# Clone the repository
git clone https://github.com/Aneesh495/quarry.git
cd quarry

# Build native shared library
make lib

# Run the complete test suite
make test

# Run microbenchmarks
make bench
```

---

## Engineering Guidelines & Code Style

### 1. Typography and Punctuation
- **Strict Prohibition of Em Dashes and En Dashes**: Do not use em dashes or en dashes anywhere in code comments, commit messages, or documentation. Use standard hyphens (`-`), colons (`:`), parentheses, or commas instead. Run `python3 verify_no_em_dashes.py` before submitting any changes.

### 2. Memory Safety & Cache Line Alignment
- All heap-allocated buffers for columnar storage, vector vectors, and hash tables must be allocated on 64-byte boundaries using `posix_memalign` and `alloc.CACHE_LINE`.
- Query-scoped allocations should use thread-local `alloc.Arena` bump allocators to prevent heap fragmentation.

### 3. Testing Policy
- Every bug identified must have a dedicated reproduction test case created in `tests/test_regressions.t` or a focused test suite that fails before applying the fix.
- All 28 test suites in `scripts/run_all_tests.sh` must pass cleanly with exit code 0 before opening a pull request.
