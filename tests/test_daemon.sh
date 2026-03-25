#!/bin/bash
# Tests for red-alert-daemon.sh

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/helpers.sh"
setup

DAEMON="$TESTS_DIR/../red-alert-daemon.sh"

echo "Testing daemon..."

# Create a patched daemon that uses temp paths
patched_daemon="$TEST_TMPDIR/daemon.sh"
sed "s|STATE_DIR=.*|STATE_DIR=\"$TEST_TMPDIR\"|;
     s|STATE_FILE=.*|STATE_FILE=\"$TEST_TMPDIR/state.json\"|;
     s|PID_FILE=.*|PID_FILE=\"$TEST_TMPDIR/daemon.pid\"|;
     s|LOG_FILE=.*|LOG_FILE=\"$TEST_TMPDIR/daemon.log\"|" "$DAEMON" > "$patched_daemon"
chmod +x "$patched_daemon"

# test_daemon_starts: launch daemon in mock mode, verify PID file created
RED_ALERT_MODE=mock RED_ALERT_MOCK_INTERVAL=1 "$patched_daemon" &
daemon_pid=$!
sleep 2

if [[ -f "$TEST_TMPDIR/daemon.pid" ]]; then
    pid_content=$(cat "$TEST_TMPDIR/daemon.pid")
    assert_equals "$pid_content" "$daemon_pid" "daemon PID file contains correct PID"
else
    echo -e "  ${RED}FAIL${RESET} daemon PID file not created"
    ((FAIL_COUNT++))
fi

# test_daemon_writes_state: mock mode creates state file with expected fields
if [[ -f "$TEST_TMPDIR/state.json" ]]; then
    state_content=$(cat "$TEST_TMPDIR/state.json")
    assert_contains "$state_content" "cat" "daemon writes state with cat field"
    assert_contains "$state_content" "cities" "daemon writes state with cities field"
    assert_contains "$state_content" "last_seen_unix" "daemon writes state with last_seen_unix"
else
    echo -e "  ${RED}FAIL${RESET} daemon state file not created"
    ((FAIL_COUNT++))
    ((FAIL_COUNT++))
    ((FAIL_COUNT++))
fi

# test_mock_alert_id: mock mode generates mock_ prefixed IDs
if [[ -f "$TEST_TMPDIR/state.json" ]]; then
    alert_id=$(jq -r '.alert_id // ""' "$TEST_TMPDIR/state.json")
    if [[ "$alert_id" == mock_* ]] || [[ "$alert_id" == "" ]]; then
        echo -e "  ${GREEN}PASS${RESET} mock mode: alert_id is mock-prefixed or empty (quiet period)"
        ((PASS_COUNT++))
    else
        echo -e "  ${RED}FAIL${RESET} mock mode: unexpected alert_id: $alert_id"
        ((FAIL_COUNT++))
    fi
fi

# test_daemon_log: log file created with startup message
if [[ -f "$TEST_TMPDIR/daemon.log" ]]; then
    assert_contains "$(cat "$TEST_TMPDIR/daemon.log")" "Daemon started" "daemon log has startup message"
else
    echo -e "  ${RED}FAIL${RESET} daemon log file not created"
    ((FAIL_COUNT++))
fi

# test_daemon_cleanup: wait for mock cycle to finish, verify PID file removed
# Mock mode exits after one cycle (6 scenarios × 1s interval)
wait "$daemon_pid" 2>/dev/null
sleep 1

if [[ ! -f "$TEST_TMPDIR/daemon.pid" ]]; then
    echo -e "  ${GREEN}PASS${RESET} daemon cleans up PID file on exit"
    ((PASS_COUNT++))
else
    echo -e "  ${RED}FAIL${RESET} daemon PID file not cleaned up"
    ((FAIL_COUNT++))
fi

# test_daemon_log_stop: log file has stop message
assert_contains "$(cat "$TEST_TMPDIR/daemon.log")" "Daemon stopping" "daemon log has stop message"

# test_mock_cycle_once: mock mode exits after one full cycle
assert_contains "$(cat "$TEST_TMPDIR/daemon.log")" "Mock cycle complete" "mock mode exits after one cycle"

cleanup
report
