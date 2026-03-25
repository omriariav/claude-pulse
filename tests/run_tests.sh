#!/bin/bash
# Test runner for claude-pulse
# Discovers and runs all test_*.sh files

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

echo "Running claude-pulse tests..."
echo "=============================="

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue
    suite_name=$(basename "$test_file" .sh)
    echo ""
    echo "--- $suite_name ---"

    if bash "$test_file"; then
        : # suite passed
    else
        FAILED_SUITES+=("$suite_name")
    fi
done

echo ""
echo "=============================="
if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    echo -e "\033[31mFailed suites: ${FAILED_SUITES[*]}\033[0m"
    exit 1
else
    echo -e "\033[32mAll test suites passed\033[0m"
    exit 0
fi
