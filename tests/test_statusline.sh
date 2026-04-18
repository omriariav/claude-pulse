#!/bin/bash
# Tests for existing claude-pulse statusline features (regression tests)

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/helpers.sh"
setup

# Force heavy density for tests (matches old full-detail format)
export CLAUDE_PULSE_DENSITY=heavy

PULSE="$TESTS_DIR/../claude-pulse"

echo "Testing statusline basics..."

# test_basic_output: minimal JSON produces expected output segments
output=$(run_pulse)
assert_contains "$output" "🧠" "basic output has brain emoji"
assert_contains "$output" "🤖" "basic output has robot emoji"
assert_contains "$output" "Opus 4.6" "basic output has model name"
assert_contains "$output" "📁" "basic output has folder emoji"
assert_contains "$output" "test" "basic output has cwd"

# test_model_detection: each model ID maps to correct name
for pair in \
    "claude-opus-4-7-20260401:Opus 4.7" \
    "claude-opus-4-7:Opus 4.7" \
    "claude-opus-4-6-20250929:Opus 4.6" \
    "claude-opus-4-6:Opus 4.6" \
    "claude-opus-4-20250512:Opus 4.5" \
    "claude-sonnet-4-6-20250929:Sonnet 4.6" \
    "claude-sonnet-4-6:Sonnet 4.6" \
    "claude-sonnet-4-5-20250514:Sonnet 4.5" \
    "claude-sonnet-4-20250514:Sonnet 4.5" \
    "claude-haiku-4-5-20251001:Haiku 4.5" \
    "claude-haiku-4-5:Haiku 4.5" \
    "claude-4-5-haiku-20260101:Haiku 4.5" \
    "claude-haiku-3-5-20241022:Haiku 3.5" \
    "claude-sonnet-3-5-20240620:Sonnet 3.5" \
    "claude-opus-3-20240229:Opus 3" \
    "claude-sonnet-3-7-20250219:Sonnet 3.7"; do
    model_id="${pair%%:*}"
    expected_name="${pair##*:}"
    out=$(echo "{\"cwd\":\"/test\",\"model\":{\"id\":\"$model_id\"},\"context_window\":{\"total_input_tokens\":50000,\"total_output_tokens\":5000,\"context_window_size\":200000}}" | "$PULSE" 2>/dev/null)
    assert_contains "$out" "$expected_name" "model detection: $model_id → $expected_name"
done

# Regression: Opus 4.7 must not fall through to the generic claude-opus-4* pattern and show "Opus 4.5".
out_opus47=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-7-20260401"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":1000000}}' | "$PULSE" 2>/dev/null)
assert_not_contains "$out_opus47" "Opus 4.5" "Opus 4.7 does not fall through to Opus 4.5"
assert_not_contains "$out_opus47" "Opus 4.6" "Opus 4.7 does not fall through to Opus 4.6"

# test_context_limit_format: 200000 → "200k", 1000000 → "1M"
out_200k=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_200k" "(200k)" "context limit: 200k format"

out_1m=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":1000000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_1m" "(1M)" "context limit: 1M format"
# regression: Opus 4.6 (1M) must never be confused with Sonnet
assert_contains "$out_1m" "Opus 4.6" "Opus 4.6 (1M) shows Opus not Sonnet"
assert_not_contains "$out_1m" "Sonnet" "Opus 4.6 (1M) does not show Sonnet"

# regression: Sonnet 4.6 must not fall back to Sonnet 4.5
out_sonnet46=$(echo '{"cwd":"/test","model":{"id":"claude-sonnet-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":1000000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_sonnet46" "Sonnet 4.6" "Sonnet 4.6 (1M) shows 4.6 not 4.5"
assert_not_contains "$out_sonnet46" "Sonnet 4.5" "Sonnet 4.6 (1M) does not show Sonnet 4.5"

# test_color_thresholds: check ANSI RGB codes based on percentage
# 25% = green (RGB 80;250;123)
out_green=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":0,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_green" "38;2;80;250;123m" "color: green at 25%"

# 60% = yellow (RGB 255;215;0)
out_yellow=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":120000,"total_output_tokens":0,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_yellow" "38;2;255;215;0m" "color: yellow at 60%"

# 90% = red (RGB 255;85;85)
out_red=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":180000,"total_output_tokens":0,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_red" "38;2;255;85;85m" "color: red at 90%"

# test_no_transcript: missing transcript shows appropriate message
out_no_transcript=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_no_transcript" "Transcript not found" "no transcript message"

# --- Conversation name (session_name) tests ---
echo ""
echo "Testing conversation name (session_name)..."

# test_session_name: native session_name field is displayed
out_sn=$(run_pulse '{"session_name":"my-cool-chat"}')
assert_contains "$out_sn" "💬 my-cool-chat" "session_name displayed"

# test_session_name_truncation: long names get truncated (heavy: 18 chars + "..")
out_long=$(run_pulse '{"session_name":"this-is-a-very-long-conversation-name"}')
assert_contains "$out_long" "💬 this-is-a-very-lon.." "long session_name truncated"
assert_not_contains "$out_long" "conversation-name" "truncation cuts the tail"

# test_session_name_empty: empty session_name shows no 💬 segment
out_empty=$(run_pulse '{"session_name":""}')
assert_not_contains "$out_empty" "💬" "empty session_name hides chat icon"

# test_session_name_null: null session_name shows no 💬 segment
out_null=$(run_pulse '{"session_name":null}')
assert_not_contains "$out_null" "💬" "null session_name hides chat icon"

# test_no_session_name: missing session_name field shows no 💬 (no transcript to fall back to)
out_missing=$(run_pulse)
assert_not_contains "$out_missing" "💬" "missing session_name hides chat icon"

# --- Rate limits tests ---
echo ""
echo "Testing rate limits..."

# test_rate_limits_displayed (heavy: %2d format, double digits have no space)
out_rates=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":53},"seven_day":{"used_percentage":66}}}')
assert_contains "$out_rates" "5h:53%" "5h rate limit shown"
assert_contains "$out_rates" "7d: 66%" "7d rate limit shown"

# test_rate_limit_colors: green <50, yellow 50-79, red 80+ (RGB codes)
out_rate_green=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":20}}}')
assert_contains "$out_rate_green" "80;250;123m" "rate green at 20%"

out_rate_yellow=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":55}}}')
assert_contains "$out_rate_yellow" "255;215;0m" "rate yellow at 55%"

out_rate_red=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":90}}}')
assert_contains "$out_rate_red" "255;85;85m" "rate red at 90%"

# --- Progress bar tests ---
echo ""
echo "Testing progress bar..."

# test_progress_bar_low: few filled blocks at low %
out_low=$(run_pulse)
# 28% ≈ 6 filled blocks
assert_contains "$out_low" "██████░" "progress bar partially filled at ~28%"

# test_progress_bar_full: capped at 100%
out_over=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":250000,"total_output_tokens":0,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_over" "████████████████████]" "progress bar full at >100%"

# --- Git diff stats tests ---
echo ""
echo "Testing git diff stats..."

# Create temp git repo with known changes
_diff_dir=$(mktemp -d)
git -C "$_diff_dir" init -q
echo "hello" > "$_diff_dir/file1.txt"
echo "world" > "$_diff_dir/file2.txt"
git -C "$_diff_dir" add . && git -C "$_diff_dir" commit -q -m "init"
echo "hello modified" > "$_diff_dir/file1.txt"
echo "new line" >> "$_diff_dir/file2.txt"
echo "brand new" > "$_diff_dir/file3.txt"
git -C "$_diff_dir" add "$_diff_dir/file3.txt"

_diff_json="{\"cwd\":\"$_diff_dir\",\"model\":{\"id\":\"claude-opus-4-6\"},\"context_window\":{\"total_input_tokens\":50000,\"total_output_tokens\":5000,\"context_window_size\":200000}}"

# test_diff_shown: dirty repo shows diff stats
out_diff=$(echo "$_diff_json" | CLAUDE_PULSE_DENSITY=heavy "$PULSE" 2>/dev/null)
assert_contains "$out_diff" "📝" "diff stats shown when dirty"
assert_contains "$out_diff" "files" "diff stats shows file count"

# test_diff_colors: green insertions, red deletions
assert_contains "$out_diff" "38;2;80;250;123m" "diff insertions colored green"
assert_contains "$out_diff" "38;2;255;85;85m" "diff deletions colored red"
assert_contains "$out_diff" "38;2;139;233;253m" "diff file count colored cyan"

# test_diff_clean: clean tree hides segment
_clean_dir=$(mktemp -d)
git -C "$_clean_dir" init -q
echo "hello" > "$_clean_dir/file1.txt"
git -C "$_clean_dir" add . && git -C "$_clean_dir" commit -q -m "init"
out_clean=$(echo "{\"cwd\":\"$_clean_dir\",\"model\":{\"id\":\"claude-opus-4-6\"},\"context_window\":{\"total_input_tokens\":50000,\"total_output_tokens\":5000,\"context_window_size\":200000}}" | CLAUDE_PULSE_DENSITY=heavy "$PULSE" 2>/dev/null)
assert_not_contains "$out_clean" "📝" "diff stats hidden when clean"

# test_diff_hide_env: CLAUDE_PULSE_HIDE_DIFF suppresses segment
out_hidden=$(echo "$_diff_json" | CLAUDE_PULSE_DENSITY=heavy CLAUDE_PULSE_HIDE_DIFF=1 "$PULSE" 2>/dev/null)
assert_not_contains "$out_hidden" "📝" "CLAUDE_PULSE_HIDE_DIFF hides diff stats"

# test_diff_minimal: compact format
out_min=$(echo "$_diff_json" | CLAUDE_PULSE_DENSITY=minimal "$PULSE" 2>/dev/null)
assert_contains "$out_min" "f" "diff stats shows file count in minimal"
assert_not_contains "$out_min" "📝" "minimal mode has no pencil emoji"

# test_diff_regular: emoji format
out_reg=$(echo "$_diff_json" | CLAUDE_PULSE_DENSITY=regular "$PULSE" 2>/dev/null)
assert_contains "$out_reg" "📝" "regular mode shows pencil emoji"

# test_diff_heavy_line1: diff stats on line 1 (not line 2) in heavy mode
_heavy_line1=$(echo "$out_diff" | head -1)
assert_contains "$_heavy_line1" "📝" "heavy mode: diff stats on line 1"

# test_diff_regular_line1: diff stats on line 1 in regular mode
_reg_line1=$(echo "$out_reg" | head -1)
assert_contains "$_reg_line1" "📝" "regular mode: diff stats on line 1"

# test_heavy_no_gap: no column padding gap after model on clean tree
_heavy_clean=$(echo "{\"cwd\":\"$_clean_dir\",\"model\":{\"id\":\"claude-opus-4-6\"},\"context_window\":{\"total_input_tokens\":50000,\"total_output_tokens\":5000,\"context_window_size\":200000},\"session_name\":\"Test\"}" | CLAUDE_PULSE_DENSITY=heavy "$PULSE" 2>/dev/null)
_heavy_clean_line1=$(echo "$_heavy_clean" | head -1)
assert_not_contains "$_heavy_clean_line1" "    " "heavy mode: no large gap on line 1 with clean tree"

rm -rf "$_diff_dir" "$_clean_dir"

# --- Minimal mode alert indicator tests ---
echo ""
echo "Testing minimal mode alert indicators..."

# Set up mock daemon (PID file pointing to our process)
setup_mock_daemon
export RED_ALERT_CITIES="Tel Aviv"

# test_minimal_alert_on: daemon running, no active alert → just 🟢 emoji
setup_expired_state "1" '["תל אביב"]'
_min_alert=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | CLAUDE_PULSE_DENSITY=minimal "$PULSE" 2>/dev/null)
assert_contains "$_min_alert" "🟢" "minimal: shows green circle"
assert_not_contains "$_min_alert" "Alerts daemon ON" "minimal: no 'Alerts daemon ON' text"

# test_regular_alert_on: same scenario in regular → shows full text
_reg_alert=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | CLAUDE_PULSE_DENSITY=regular "$PULSE" 2>/dev/null)
assert_contains "$_reg_alert" "🟢 Alerts daemon ON" "regular: shows full daemon ON text"

# test_minimal_version_mismatch: daemon running but version differs → just 🟡 emoji
# Stage a fake HOME with red-alert-daemon.sh so _expected_ver parses hermetically
_fake_home="${TEST_TMPDIR}/fakehome"
mkdir -p "${_fake_home}/.claude"
echo -e '#!/bin/bash\n# red-alert-daemon.sh v9.9.9: fake' > "${_fake_home}/.claude/red-alert-daemon.sh"
export RED_ALERT_STATE_DIR="$TEST_TMPDIR"
echo "0.0.0" > "${TEST_TMPDIR}/daemon_version"
setup_mock_daemon
setup_expired_state "1" '["תל אביב"]'
_min_mismatch=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | HOME="$_fake_home" CLAUDE_PULSE_DENSITY=minimal "$PULSE" 2>/dev/null)
assert_contains "$_min_mismatch" "🟡" "minimal: shows yellow circle for version mismatch"
assert_not_contains "$_min_mismatch" "update pending" "minimal: no 'update pending' text"

# test_regular_version_mismatch: same in regular → full text
_reg_mismatch=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | HOME="$_fake_home" CLAUDE_PULSE_DENSITY=regular "$PULSE" 2>/dev/null)
assert_contains "$_reg_mismatch" "🟡 Daemon v0.0.0 (update pending)" "regular: shows full version mismatch text"
rm -f "${TEST_TMPDIR}/daemon_version"
rm -rf "$_fake_home"
unset RED_ALERT_STATE_DIR

# test_minimal_daemon_not_running: daemon not running → just 🔕 emoji
rm -f "$RED_ALERT_PID_FILE"
_min_off=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | CLAUDE_PULSE_DENSITY=minimal "$PULSE" 2>/dev/null)
assert_contains "$_min_off" "🔕" "minimal: shows muted bell"
assert_not_contains "$_min_off" "not running" "minimal: no 'not running' text"

# test_regular_daemon_not_running: same in regular → full text
_reg_off=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | CLAUDE_PULSE_DENSITY=regular "$PULSE" 2>/dev/null)
assert_contains "$_reg_off" "🔕 Alerts daemon not running" "regular: shows full not running text"

unset RED_ALERT_CITIES

cleanup
report
