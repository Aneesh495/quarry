# ==============================================================================
# Makefile for Quarry Columnar OLAP Engine & Vector Database
# ==============================================================================

SHELL := /bin/bash
TERRA := $(shell which terra 2>/dev/null || echo "$$HOME/.local/bin/terra")
PYTHON := python3

.PHONY: all lib test bench cli lint clean help data profile

all: lib ## Build Quarry shared native library and verify environment

lib: ## Compile native shared library (libquarry.dylib / libquarry.so)
	@echo "--> Building native shared library via Terra..."
	@mkdir -p lib
	$(TERRA) scripts/build_libquarry.t

test: lib ## Run the complete 28-suite master verification test suite
	@echo "--> Executing full test suite..."
	./scripts/run_all_tests.sh

bench: lib ## Run the performance and micro-benchmark suite
	@echo "--> Executing benchmark suite..."
	./scripts/run_benchmarks.sh

cli: ## Run interactive CLI verification
	@echo "--> Testing CLI executable..."
	./bin/quarry --version
	./bin/quarry --help

lint: ## Verify zero em dashes or en dashes across repository
	@echo "--> Running strict typography and style audit..."
	$(PYTHON) verify_no_em_dashes.py

data: ## Generate synthetic TPC-H and vector embedding datasets
	@echo "--> Generating sample datasets..."
	$(PYTHON) scripts/generate_sample_data.py --lineitem-rows 5000 --customer-rows 500 --orders-rows 1500
	$(PYTHON) scripts/generate_embeddings.py --num-vectors 500 --dim 64

profile: lib ## Run fine-grained query pipeline stage profiler
	@echo "--> Running query pipeline profiler..."
	$(TERRA) scripts/profile_query.t

clean: ## Clean build artifacts, temporary test files, and logs
	@echo "--> Cleaning build artifacts and caches..."
	@rm -rf tests/test_c_api_bin
	@rm -rf data/sample/*.csv
	@rm -rf tmp/ *.tmp *.log
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	@echo "Clean completed."

help: ## Show this help message
	@echo "Quarry Engine Build & Test System"
	@echo ""
	@echo "Available Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
