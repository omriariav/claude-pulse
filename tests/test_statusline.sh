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

cleanup
report
