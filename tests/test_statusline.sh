#!/bin/bash
# Tests for existing claude-pulse statusline features (regression tests)

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/helpers.sh"
setup

PULSE="$TESTS_DIR/../claude-pulse"

echo "Testing statusline basics..."

# test_basic_output: minimal JSON produces expected output segments
output=$(run_pulse)
assert_contains "$output" "🧠" "basic output has brain emoji"
assert_contains "$output" "🤖" "basic output has robot emoji"
assert_contains "$output" "Opus 4.6" "basic output has model name"
assert_contains "$output" "📁" "basic output has folder emoji"
assert_contains "$output" "/test" "basic output has cwd"

# test_model_detection: each model ID maps to correct name
for pair in \
    "claude-opus-4-6-20250929:Opus 4.6" \
    "claude-opus-4-20250512:Opus 4.5" \
    "claude-sonnet-4-20250514:Sonnet 4.5" \
    "claude-haiku-3-5-20241022:Haiku 3.5" \
    "claude-sonnet-3-5-20240620:Sonnet 3.5" \
    "claude-opus-3-20240229:Opus 3" \
    "claude-sonnet-3-7-20250219:Sonnet 3.7"; do
    model_id="${pair%%:*}"
    expected_name="${pair##*:}"
    out=$(echo "{\"cwd\":\"/test\",\"model\":{\"id\":\"$model_id\"},\"context_window\":{\"total_input_tokens\":50000,\"total_output_tokens\":5000,\"context_window_size\":200000}}" | "$PULSE" 2>/dev/null)
    assert_contains "$out" "$expected_name" "model detection: $model_id → $expected_name"
done

# test_context_limit_format: 200000 → "200k", 1000000 → "1M"
out_200k=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_200k" "(200k)" "context limit: 200k format"

out_1m=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":1000000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_1m" "(1M)" "context limit: 1M format"

# test_color_thresholds: check ANSI codes based on percentage
# 25% = green (32m)
out_green=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":0,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_green" "[32m" "color: green at 25%"

# 60% = yellow (33m)
out_yellow=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":120000,"total_output_tokens":0,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_yellow" "[33m" "color: yellow at 60%"

# 90% = red (31m)
out_red=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":180000,"total_output_tokens":0,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_red" "[31m" "color: red at 90%"

# test_no_transcript: missing transcript shows appropriate message
out_no_transcript=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_no_transcript" "Transcript not found" "no transcript message"

# --- Conversation name (session_name) tests ---
echo ""
echo "Testing conversation name (session_name)..."

# test_session_name: native session_name field is displayed
out_sn=$(run_pulse '{"session_name":"my-cool-chat"}')
assert_contains "$out_sn" "💬 my-cool-chat" "session_name displayed"

# test_session_name_truncation: long names get truncated to 18 chars + ".."
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

# test_rate_limits_displayed
out_rates=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":53},"seven_day":{"used_percentage":66}}}')
assert_contains "$out_rates" "5h: 53%" "5h rate limit shown"
assert_contains "$out_rates" "7d: 66%" "7d rate limit shown"

# test_rate_limit_colors: green <50, yellow 50-79, red 80+
out_rate_green=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":20}}}')
assert_contains "$out_rate_green" "[32m5h" "rate green at 20%"

out_rate_yellow=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":55}}}')
assert_contains "$out_rate_yellow" "[33m5h" "rate yellow at 55%"

out_rate_red=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":90}}}')
assert_contains "$out_rate_red" "[31m5h" "rate red at 90%"

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

cleanup
report
