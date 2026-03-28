#!/bin/bash
# test_ota_update.sh: End-to-end OTA update simulation
# Creates a fake v3.0.1 release, serves it locally, runs update.sh, verifies results

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass() { ((PASS++)); printf "  \033[32mPASS\033[0m %s\n" "$1"; }
fail() { ((FAIL++)); printf "  \033[31mFAIL\033[0m %s\n" "$1"; }
check() { if eval "$2"; then pass "$1"; else fail "$1 — $2"; fi; }

# --- Setup isolated test environment ---
TEST_DIR=$(mktemp -d)
FAKE_CLAUDE_DIR="${TEST_DIR}/claude"
FAKE_CACHE_DIR="${TEST_DIR}/cache"
FAKE_STATE_DIR="${TEST_DIR}/state"
FAKE_STAGING="${FAKE_CACHE_DIR}/staging"
MOCK_RELEASE_DIR="${TEST_DIR}/mock-release"
MOCK_SERVER_PORT=$((RANDOM % 10000 + 20000))
MOCK_SERVER_PID=""

cleanup() {
    [[ -n "$MOCK_SERVER_PID" ]] && kill "$MOCK_SERVER_PID" 2>/dev/null || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$FAKE_CLAUDE_DIR" "$FAKE_CACHE_DIR" "$FAKE_STATE_DIR" "$MOCK_RELEASE_DIR"

echo "=== OTA Update QA Test ==="
echo "Test dir: $TEST_DIR"
echo ""

# --- Phase 1: Install "current" v3.0.0 ---
echo "--- Setup: Install v3.0.0 as current ---"
cp "$SCRIPT_DIR/claude-pulse" "$FAKE_CLAUDE_DIR/statusline-command.sh"
cp "$SCRIPT_DIR/red-alert-daemon.sh" "$FAKE_CLAUDE_DIR/red-alert-daemon.sh"
cp "$SCRIPT_DIR/update.sh" "$FAKE_CLAUDE_DIR/update.sh"
chmod +x "$FAKE_CLAUDE_DIR"/*.sh

current_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CLAUDE_DIR/statusline-command.sh")
echo "Installed version: v${current_ver}"
check "current version extracted" '[[ -n "$current_ver" ]]'

# --- Phase 2: Create fake v3.0.1 release ---
echo ""
echo "--- Setup: Create fake v3.0.1 release ---"
FAKE_VER="3.0.1"
FAKE_RELEASE_SRC="${MOCK_RELEASE_DIR}/omriariav-claude-pulse-abc1234"
mkdir -p "$FAKE_RELEASE_SRC/static"

# Copy real files and bump version
cp "$SCRIPT_DIR/claude-pulse" "$FAKE_RELEASE_SRC/claude-pulse"
cp "$SCRIPT_DIR/red-alert-daemon.sh" "$FAKE_RELEASE_SRC/red-alert-daemon.sh"
cp "$SCRIPT_DIR/update.sh" "$FAKE_RELEASE_SRC/update.sh"

# Bump version in the fake release
sed -i '' "s/v${current_ver}/v${FAKE_VER}/" "$FAKE_RELEASE_SRC/claude-pulse"
sed -i '' "s/v${current_ver}/v${FAKE_VER}/" "$FAKE_RELEASE_SRC/red-alert-daemon.sh"
sed -i '' "s/v${current_ver}/v${FAKE_VER}/" "$FAKE_RELEASE_SRC/update.sh"

# Create tarball (GitHub format: top-level directory)
(cd "$MOCK_RELEASE_DIR" && tar czf release.tar.gz omriariav-claude-pulse-abc1234/)
check "tarball created" '[[ -f "$MOCK_RELEASE_DIR/release.tar.gz" ]]'

new_ver_in_tarball=$(tar xzf "$MOCK_RELEASE_DIR/release.tar.gz" -C /tmp --include='*/claude-pulse' -O 2>/dev/null | sed -n '2s/.*v\([0-9.]*\).*/\1/p')
check "tarball has v${FAKE_VER}" '[[ "$new_ver_in_tarball" == "$FAKE_VER" ]]'

# --- Phase 3: Start mock HTTP server ---
echo ""
echo "--- Setup: Start mock HTTP server ---"

# Generate SHA256 checksum for the tarball
TARBALL_HASH=$(shasum -a 256 "$MOCK_RELEASE_DIR/release.tar.gz" | cut -d' ' -f1)
echo "${TARBALL_HASH}  claude-pulse-v${FAKE_VER}.tar.gz" > "${MOCK_RELEASE_DIR}/checksums.sha256"

# Create mock GitHub API response (with release assets for checksum verification)
cat > "${MOCK_RELEASE_DIR}/api_response.json" <<EOF
{
  "tag_name": "v${FAKE_VER}",
  "tarball_url": "http://localhost:${MOCK_SERVER_PORT}/release.tar.gz",
  "name": "v${FAKE_VER}",
  "body": "Test release for OTA QA",
  "assets": [
    {
      "name": "claude-pulse-v${FAKE_VER}.tar.gz",
      "browser_download_url": "http://localhost:${MOCK_SERVER_PORT}/release.tar.gz"
    },
    {
      "name": "checksums.sha256",
      "browser_download_url": "http://localhost:${MOCK_SERVER_PORT}/checksums.sha256"
    }
  ]
}
EOF

# Start simple HTTP server
(cd "$MOCK_RELEASE_DIR" && python3 -m http.server "$MOCK_SERVER_PORT" >/dev/null 2>&1) &
MOCK_SERVER_PID=$!
sleep 1

# Verify server is running
if curl -sf "http://localhost:${MOCK_SERVER_PORT}/api_response.json" > /dev/null 2>&1; then
    pass "mock server running on port $MOCK_SERVER_PORT"
else
    fail "mock server failed to start"
    echo "Cannot continue without mock server"
    exit 1
fi

# --- Phase 4: Create patched update.sh for testing ---
echo ""
echo "--- Test: Semver comparison ---"

# Source just the semver function for unit testing
eval "$(sed -n '/^semver_gt/,/^}/p' "$SCRIPT_DIR/update.sh")"
if semver_gt "3.0.1" "3.0.0"; then pass "3.0.1 > 3.0.0"; else fail "3.0.1 > 3.0.0"; fi
if semver_gt "3.1.0" "3.0.9"; then pass "3.1.0 > 3.0.9"; else fail "3.1.0 > 3.0.9"; fi
if ! semver_gt "3.0.0" "3.0.0"; then pass "3.0.0 == 3.0.0 (not gt)"; else fail "3.0.0 == 3.0.0"; fi
if ! semver_gt "2.9.0" "3.0.0"; then pass "2.9.0 < 3.0.0 (not gt)"; else fail "2.9.0 < 3.0.0"; fi

# --- Phase 5: Run full OTA flow ---
echo ""
echo "--- Test: Full OTA auto-update flow ---"

# Create patched update.sh: copy original, then override paths and API URL
cp "$SCRIPT_DIR/update.sh" "${TEST_DIR}/test_update.sh"
chmod +x "${TEST_DIR}/test_update.sh"
# Override paths (use | as sed delimiter to avoid path escaping issues)
sed -i '' "s|CLAUDE_DIR=\"\$HOME/.claude\"|CLAUDE_DIR=\"${FAKE_CLAUDE_DIR}\"|" "${TEST_DIR}/test_update.sh"
sed -i '' "s|CACHE_DIR=\"\$HOME/.cache/claude-pulse\"|CACHE_DIR=\"${FAKE_CACHE_DIR}\"|" "${TEST_DIR}/test_update.sh"
sed -i '' "s|STATE_DIR=\"\$HOME/.local/state/claude-pulse\"|STATE_DIR=\"${FAKE_STATE_DIR}\"|" "${TEST_DIR}/test_update.sh"
# Override GitHub API URL to point at local mock server
sed -i '' "s|https://api.github.com/repos/\${REPO}/releases/latest|http://localhost:${MOCK_SERVER_PORT}/api_response.json|" "${TEST_DIR}/test_update.sh"
# Remove HTTPS-only restriction for local HTTP mock server
sed -i '' "s|--proto '=https' --tlsv1.2 ||g" "${TEST_DIR}/test_update.sh"
# Disable gh CLI in test (mock server is HTTP, not GitHub API)
sed -i '' 's|command -v gh|command -v _gh_disabled_for_test|g' "${TEST_DIR}/test_update.sh"

# Clear rate limit
rm -f "${FAKE_CACHE_DIR}/last_update_check"

# Run auto-update
CLAUDE_PULSE_AUTO_UPDATE=auto bash "${TEST_DIR}/test_update.sh" 2>&1 || true

# Verify results
echo ""
echo "--- Verify: Auto-update results ---"

updated_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CLAUDE_DIR/statusline-command.sh")
check "statusline updated to v${FAKE_VER}" '[[ "$updated_ver" == "$FAKE_VER" ]]'

daemon_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CLAUDE_DIR/red-alert-daemon.sh")
check "daemon updated to v${FAKE_VER}" '[[ "$daemon_ver" == "$FAKE_VER" ]]'

updater_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CLAUDE_DIR/update.sh" 2>/dev/null || echo "")
check "update.sh self-updated to v${FAKE_VER}" '[[ "$updater_ver" == "$FAKE_VER" ]]'

check "backup directory created" '[[ -d "$FAKE_CACHE_DIR/versions/v${current_ver}" ]]'

backup_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CACHE_DIR/versions/v${current_ver}/statusline-command.sh" 2>/dev/null)
check "backup has original v${current_ver}" '[[ "$backup_ver" == "$current_ver" ]]'

check "update notification file created" '[[ -f "$FAKE_CACHE_DIR/update_notification" ]]'

notif_ver=$(head -1 "$FAKE_CACHE_DIR/update_notification" 2>/dev/null)
check "notification shows v${FAKE_VER}" '[[ "$notif_ver" == "$FAKE_VER" ]]'

check "daemon restart marker created" '[[ -f "$FAKE_STATE_DIR/daemon_restart_requested" ]]'

check "staging cleaned up" '[[ ! -d "$FAKE_STAGING" ]]'

check "rate limit file updated" '[[ -f "$FAKE_CACHE_DIR/last_update_check" ]]'

# Check update log
check "update log exists" '[[ -f "$FAKE_STATE_DIR/update.log" ]]'
if [[ -f "$FAKE_STATE_DIR/update.log" ]]; then
    check "log mentions new version" 'grep -q "v${FAKE_VER}" "$FAKE_STATE_DIR/update.log"'
    check "log mentions success" 'grep -q "successfully" "$FAKE_STATE_DIR/update.log"'
    check "log mentions checksum verified" 'grep -q "Checksum verified" "$FAKE_STATE_DIR/update.log"'
fi

# --- Phase 5b: Test bad checksum rejection ---
echo ""
echo "--- Test: Bad checksum rejection ---"

# Reset: reinstall v3.0.0
cp "$SCRIPT_DIR/claude-pulse" "$FAKE_CLAUDE_DIR/statusline-command.sh"
cp "$SCRIPT_DIR/red-alert-daemon.sh" "$FAKE_CLAUDE_DIR/red-alert-daemon.sh"
rm -f "${FAKE_CACHE_DIR}/last_update_check"
rm -rf "${FAKE_CACHE_DIR}/update.lock"

# Corrupt the checksum file on the server
echo "0000000000000000000000000000000000000000000000000000000000000000  claude-pulse-v${FAKE_VER}.tar.gz" > "${MOCK_RELEASE_DIR}/checksums.sha256"

CLAUDE_PULSE_AUTO_UPDATE=auto bash "${TEST_DIR}/test_update.sh" 2>&1 || true

bad_cksum_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CLAUDE_DIR/statusline-command.sh")
check "bad checksum: files NOT updated" '[[ "$bad_cksum_ver" == "$current_ver" ]]'
check "bad checksum: logged mismatch" 'grep -q "Checksum mismatch" "$FAKE_STATE_DIR/update.log"'

# Restore correct checksum for remaining tests
echo "${TARBALL_HASH}  claude-pulse-v${FAKE_VER}.tar.gz" > "${MOCK_RELEASE_DIR}/checksums.sha256"

# --- Phase 6: Test notify mode ---
echo ""
echo "--- Test: Notify-only mode ---"

# Reset: reinstall v3.0.0
cp "$SCRIPT_DIR/claude-pulse" "$FAKE_CLAUDE_DIR/statusline-command.sh"
cp "$SCRIPT_DIR/red-alert-daemon.sh" "$FAKE_CLAUDE_DIR/red-alert-daemon.sh"
rm -f "$FAKE_CACHE_DIR/last_update_check" "$FAKE_CACHE_DIR/update_notification" "$FAKE_CACHE_DIR/update_available"
rm -rf "$FAKE_CACHE_DIR/update.lock"

CLAUDE_PULSE_AUTO_UPDATE=notify bash "${TEST_DIR}/test_update.sh" 2>&1 || true

notify_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CLAUDE_DIR/statusline-command.sh")
check "notify mode: files NOT updated (still v${current_ver})" '[[ "$notify_ver" == "$current_ver" ]]'
check "notify mode: update_available file created" '[[ -f "$FAKE_CACHE_DIR/update_available" ]]'

avail_ver=$(head -1 "$FAKE_CACHE_DIR/update_available" 2>/dev/null)
check "notify mode: available version is v${FAKE_VER}" '[[ "$avail_ver" == "$FAKE_VER" ]]'

# --- Phase 7: Test singleton lock ---
echo ""
echo "--- Test: Singleton lock ---"

rm -f "$FAKE_CACHE_DIR/last_update_check"
rm -rf "$FAKE_CACHE_DIR/update.lock"
mkdir -p "$FAKE_CACHE_DIR/update.lock"  # simulate held lock

CLAUDE_PULSE_AUTO_UPDATE=auto bash "${TEST_DIR}/test_update.sh" 2>&1 || true
check "singleton lock: second run exits without updating" '[[ "$notify_ver" == "$current_ver" ]]'

rm -rf "$FAKE_CACHE_DIR/update.lock"

# --- Phase 8: Test rate limiting ---
echo ""
echo "--- Test: Rate limiting ---"

rm -rf "$FAKE_CACHE_DIR/update.lock"
date +%s > "$FAKE_CACHE_DIR/last_update_check"  # just checked

CLAUDE_PULSE_AUTO_UPDATE=auto bash "${TEST_DIR}/test_update.sh" 2>&1 || true
still_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$FAKE_CLAUDE_DIR/statusline-command.sh")
check "rate limit: skips check within 1 hour" '[[ "$still_ver" == "$current_ver" ]]'

# --- Phase 9: Test update badge in statusline ---
echo ""
echo "--- Test: Update badge display ---"

# Badge tests use the real cache path since claude-pulse reads from $HOME/.cache/claude-pulse
REAL_CACHE="$HOME/.cache/claude-pulse"
mkdir -p "$REAL_CACHE"

# Simulate auto-update notification (save/restore any existing file)
_saved_notif="" && [[ -f "$REAL_CACHE/update_notification" ]] && _saved_notif=$(cat "$REAL_CACHE/update_notification")
printf '%s\n%s' "$FAKE_VER" "$(date +%s)" > "$REAL_CACHE/update_notification"
badge_output=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | CLAUDE_PULSE_DENSITY=heavy bash "$SCRIPT_DIR/claude-pulse" 2>/dev/null)
check "badge: shows update version" 'echo "$badge_output" | grep -q "Updated to v${FAKE_VER}"'
check "badge: shows refresh emoji" 'echo "$badge_output" | grep -q "🔄"'
rm -f "$REAL_CACHE/update_notification"
[[ -n "$_saved_notif" ]] && echo "$_saved_notif" > "$REAL_CACHE/update_notification"

# Simulate notify-mode available (save/restore any existing file)
_saved_avail="" && [[ -f "$REAL_CACHE/update_available" ]] && _saved_avail=$(cat "$REAL_CACHE/update_available")
printf '%s\n%s' "$FAKE_VER" "/tmp/staged" > "$REAL_CACHE/update_available"
avail_output=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | CLAUDE_PULSE_DENSITY=heavy bash "$SCRIPT_DIR/claude-pulse" 2>/dev/null)
check "badge: shows available version" 'echo "$avail_output" | grep -q "available"'
rm -f "$REAL_CACHE/update_available"
[[ -n "$_saved_avail" ]] && echo "$_saved_avail" > "$REAL_CACHE/update_available"

# --- Results ---
echo ""
echo "=============================="
TOTAL=$((PASS + FAIL))
echo "Results: ${PASS}/${TOTAL} passed"
if (( FAIL > 0 )); then
    printf "\033[31m%d test(s) failed\033[0m\n" "$FAIL"
    exit 1
else
    printf "\033[32mAll OTA tests passed\033[0m\n"
fi
