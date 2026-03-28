#!/bin/bash
# Test helpers for claude-pulse test suite

PASS_COUNT=0
FAIL_COUNT=0
TEST_TMPDIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

setup() {
    TEST_TMPDIR=$(mktemp -d)
    # Override state/pid file locations for tests
    export RED_ALERT_STATE_FILE="${TEST_TMPDIR}/red_alert_state.json"
    export RED_ALERT_PID_FILE="${TEST_TMPDIR}/red_alert_daemon.pid"
}

cleanup() {
    [[ -n "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
    unset RED_ALERT_CITIES RED_ALERT_MODE RED_ALERT_STATE_FILE RED_ALERT_PID_FILE
}

# Run claude-pulse with minimal JSON input
run_pulse() {
    local extra_json="${1:-}"
    local json='{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}'
    if [[ -n "$extra_json" ]]; then
        json=$(echo "$json" | jq ". + $extra_json")
    fi
    echo "$json" | CLAUDE_PULSE_DENSITY="${CLAUDE_PULSE_DENSITY:-heavy}" "$SCRIPT_DIR/claude-pulse" 2>/dev/null
}

# Fake a running daemon (write current PID to PID file so indicator shows 🔔 not 🔕)
setup_mock_daemon() {
    echo $$ > "$RED_ALERT_PID_FILE"
}

# Write mock alert state file
setup_mock_state() {
    local cat="$1"
    local cities_json="$2"
    local title="${3:-ירי רקטות וטילים}"
    local last_seen="${4:-$(date +%s)}"
    mkdir -p "$(dirname "$RED_ALERT_STATE_FILE")"
    cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"test_123","cat":"$cat","title":"$title","cities":$cities_json,"last_seen_unix":$last_seen,"cleared_unix":0}
EOF
}

# Write expired alert state (older than 60s)
setup_expired_state() {
    local cat="$1"
    local cities_json="$2"
    local expired_time=$(( $(date +%s) - 120 ))
    setup_mock_state "$cat" "$cities_json" "ירי רקטות וטילים" "$expired_time"
}

assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="$3"
    if echo "$output" | grep -qF "$expected"; then
        echo -e "  ${GREEN}PASS${RESET} $test_name"
        ((PASS_COUNT++))
    else
        echo -e "  ${RED}FAIL${RESET} $test_name"
        echo "    Expected to contain: $expected"
        echo "    Got: $output"
        ((FAIL_COUNT++))
    fi
}

assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local test_name="$3"
    if echo "$output" | grep -qF "$unexpected"; then
        echo -e "  ${RED}FAIL${RESET} $test_name"
        echo "    Expected NOT to contain: $unexpected"
        echo "    Got: $output"
        ((FAIL_COUNT++))
    else
        echo -e "  ${GREEN}PASS${RESET} $test_name"
        ((PASS_COUNT++))
    fi
}

assert_equals() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo -e "  ${GREEN}PASS${RESET} $test_name"
        ((PASS_COUNT++))
    else
        echo -e "  ${RED}FAIL${RESET} $test_name"
        echo "    Expected: $expected"
        echo "    Got: $actual"
        ((FAIL_COUNT++))
    fi
}

report() {
    local total=$((PASS_COUNT + FAIL_COUNT))
    echo ""
    echo "Results: $PASS_COUNT/$total passed"
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}$FAIL_COUNT test(s) failed${RESET}"
        return 1
    else
        echo -e "${GREEN}All tests passed${RESET}"
        return 0
    fi
}
