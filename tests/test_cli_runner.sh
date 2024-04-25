#!/bin/bash
# test_cli_runner.sh
# End-to-end integration test verifying Quarry CLI executable and arguments.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== Running Quarry CLI Launcher & Argument Tests ==="

# 1. Test --version
echo "Testing: bin/quarry --version"
VERSION_OUT=$(./bin/quarry --version)
if [[ "$VERSION_OUT" != *"v1.0.0"* ]]; then
    echo "FAIL: expected version v1.0.0, got: $VERSION_OUT"
    exit 1
fi
echo "PASS: Version flag output: $VERSION_OUT"

# 2. Test --help
echo "Testing: bin/quarry --help"
HELP_OUT=$(./bin/quarry --help)
if [[ "$HELP_OUT" != *"Usage: quarry"* ]]; then
    echo "FAIL: expected Usage header, got: $HELP_OUT"
    exit 1
fi
echo "PASS: Help flag displayed CLI documentation"

# 3. Test -c command execution
echo "Testing: bin/quarry -c 'SELECT 1'"
CMD_OUT=$(./bin/quarry -c "SELECT 1")
if [[ "$CMD_OUT" != *"Query executed successfully"* ]]; then
    echo "FAIL: query command failed: $CMD_OUT"
    exit 1
fi
echo "PASS: Non-interactive SQL command execution passed"

echo "=== ALL CLI RUNNER TESTS PASSED (3/3) ==="
