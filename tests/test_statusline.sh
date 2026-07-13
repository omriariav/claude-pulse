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
    "claude-opus-4-8[1m]:Opus 4.8" \
    "claude-opus-4-8:Opus 4.8" \
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

# Regression: Opus 4.8 (incl. [1m] context suffix) must not fall through to Opus 4.5.
out_opus48=$(echo '{"cwd":"/test","model":{"id":"claude-opus-4-8[1m]"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":1000000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_opus48" "Opus 4.8" "Opus 4.8 detected from claude-opus-4-8[1m]"
assert_not_contains "$out_opus48" "Opus 4.5" "Opus 4.8 does not fall through to Opus 4.5"

# Future-proofing: an unseen modern ID is parsed generically, not shown as bare "Claude".
out_future=$(echo '{"cwd":"/test","model":{"id":"claude-sonnet-5-0-20270101"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_future" "Sonnet 5.0" "unseen modern ID (sonnet-5-0) parsed generically"

# Unknown / non-modern ID falls back to Claude Code's own model.display_name.
out_dn=$(echo '{"cwd":"/test","model":{"id":"claude-neo-quantum","display_name":"Neo Quantum"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | "$PULSE" 2>/dev/null)
assert_contains "$out_dn" "Neo Quantum" "unknown ID falls back to display_name"

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

# Fable quota is rendered in every density when a payload carries the internal
# bucket name (seven_day_overage_included). NOTE: Claude Code 2.1.207 does not
# actually emit this key in statusline payloads (see the 2.1.207 shape tests
# below) — this exercises the future-proof path for a version that does.
for density in minimal regular heavy taboola; do
    out_fable=$(echo '{"cwd":"/test","model":{"id":"claude-fable-5"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":63},"seven_day_overage_included":{"used_percentage":96}}}' |
        CLAUDE_PULSE_DENSITY="$density" "$PULSE" 2>/dev/null)
    assert_contains "$out_fable" "Fable:" "Fable quota shown in $density density"
    assert_contains "$out_fable" "96%" "Fable quota value shown in $density density"
done

# Future semantic keys and scoped metadata take precedence over the legacy key.
out_fable_alias=$(run_pulse '{"rate_limits":{"seven_day_fable":{"used_percentage":71},"seven_day_overage_included":{"used_percentage":99}}}')
assert_contains "$out_fable_alias" "Fable: 71%" "semantic Fable key preferred over legacy alias"
assert_not_contains "$out_fable_alias" "Fable: 99%" "legacy alias ignored when semantic key exists"

out_fable_scoped=$(run_pulse '{"rate_limits":{"future_weekly_bucket":{"used_percentage":42,"scope":{"model":{"display_name":"Claude Fable 5"}}}}}')
assert_contains "$out_fable_scoped" "Fable: 42%" "Fable quota discovered from scope metadata"

out_fable_utilization=$(run_pulse '{"rate_limits":{"fable":{"utilization":0.37}}}')
assert_contains "$out_fable_utilization" "Fable: 37%" "Fable quota accepts fractional utilization shape"

out_no_fable=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":34}}}')
assert_not_contains "$out_no_fable" "Fable:" "Fable quota hidden when Anthropic does not advertise one"

# --- Claude Code 2.1.207 payload shape ---
echo ""
echo "Testing Claude Code 2.1.207 payload shape..."

# A faithful replica of a real 2.1.207 statusline payload: rate_limits carries
# ONLY five_hour and seven_day. The builder in 2.1.207 drops the internal
# seven_day_overage_included (Fable) bucket even when /usage shows a
# "Current week (Fable)" row, so the Fable segment must stay hidden.
payload_207='{"session_id":"diag-session-abc123","transcript_path":"/nonexistent-transcript.jsonl","cwd":"/test","prompt_id":"diag-prompt-xyz","effort":{"level":"medium"},"model":{"id":"claude-fable-5","display_name":"Fable 5"},"workspace":{"current_dir":"/test","project_dir":"/test","added_dirs":[]},"version":"2.1.207","output_style":{"name":"default"},"cost":{"total_cost_usd":7.99,"total_duration_ms":1000,"total_api_duration_ms":500,"total_lines_added":1,"total_lines_removed":1},"context_window":{"total_input_tokens":581756,"total_output_tokens":838,"context_window_size":1000000,"current_usage":{"input_tokens":2,"output_tokens":838,"cache_creation_input_tokens":306,"cache_read_input_tokens":581448},"used_percentage":58,"remaining_percentage":42},"exceeds_200k_tokens":true,"fast_mode":false,"thinking":{"enabled":true},"rate_limits":{"five_hour":{"used_percentage":32,"resets_at":1783964400},"seven_day":{"used_percentage":4,"resets_at":1784494800}}}'

for density in minimal regular heavy taboola; do
    out_207=$(echo "$payload_207" | CLAUDE_PULSE_DENSITY="$density" "$PULSE" 2>/dev/null)
    assert_contains "$out_207" "5h:" "2.1.207 payload shows 5h limit in $density density"
    assert_contains "$out_207" "7d:" "2.1.207 payload shows 7d limit in $density density"
    assert_not_contains "$out_207" "Fable:" "2.1.207 payload hides Fable segment in $density density"
done

# --- Rate-limits diagnostic (CLAUDE_PULSE_DEBUG_RATE_LIMITS) ---
echo ""
echo "Testing rate-limits diagnostic..."

diag_file="$TEST_TMPDIR/rl-diag.json"

# Not written unless explicitly enabled
echo "$payload_207" | CLAUDE_PULSE_DEBUG_RATE_LIMITS="" CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE="$diag_file" "$PULSE" >/dev/null 2>&1
assert_equals "$([[ -e "$diag_file" ]] && echo present || echo absent)" "absent" "diagnostic not written when env var unset"

# One-shot capture with the exact 2.1.207 payload
echo "$payload_207" | CLAUDE_PULSE_DEBUG_RATE_LIMITS=1 CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE="$diag_file" "$PULSE" >/dev/null 2>&1
assert_equals "$([[ -f "$diag_file" ]] && echo present || echo absent)" "present" "diagnostic file created when enabled"
diag=$(cat "$diag_file" 2>/dev/null)
assert_contains "$diag" '"captured_at"' "diagnostic records capture time"
assert_contains "$diag" '"claude_code_version":"2.1.207"' "diagnostic records Claude Code version"
assert_contains "$diag" '"model":"claude-fable-5"' "diagnostic records model id"
assert_contains "$diag" '"five_hour"' "diagnostic records five_hour key"
assert_contains "$diag" '"seven_day"' "diagnostic records seven_day key"

# Privacy: key names only — no values, ids, paths, or costs may leak
assert_not_contains "$diag" "diag-session-abc123" "diagnostic omits session id"
assert_not_contains "$diag" "diag-prompt-xyz" "diagnostic omits prompt id"
assert_not_contains "$diag" "nonexistent-transcript" "diagnostic omits transcript path"
assert_not_contains "$diag" "used_percentage" "diagnostic omits rate-limit values"
assert_not_contains "$diag" "resets_at" "diagnostic omits reset timestamps"
assert_not_contains "$diag" "7.99" "diagnostic omits session cost"
assert_not_contains "$diag" '"cwd"' "diagnostic omits cwd"

# One-shot: a later render with a different payload must not overwrite it
echo '{"cwd":"/test","version":"9.9.9","model":{"id":"claude-fable-5"},"context_window":{"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000},"rate_limits":{"seven_day_overage_included":{"used_percentage":96}}}' |
    CLAUDE_PULSE_DEBUG_RATE_LIMITS=1 CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE="$diag_file" "$PULSE" >/dev/null 2>&1
assert_equals "$(cat "$diag_file" 2>/dev/null)" "$diag" "diagnostic is one-shot (second render leaves it untouched)"

# A payload that DOES carry a Fable bucket gets its key name captured
diag_file2="$TEST_TMPDIR/rl-diag-fable.json"
echo '{"cwd":"/test","version":"2.2.0","model":{"id":"claude-fable-5"},"context_window":{"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":1},"seven_day":{"used_percentage":2},"seven_day_overage_included":{"used_percentage":96}}}' |
    CLAUDE_PULSE_DEBUG_RATE_LIMITS=1 CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE="$diag_file2" "$PULSE" >/dev/null 2>&1
assert_contains "$(cat "$diag_file2" 2>/dev/null)" '"seven_day_overage_included"' "diagnostic captures Fable bucket key when present"

# Missing rate_limits object degrades to an empty key list, not a crash
diag_file3="$TEST_TMPDIR/rl-diag-empty.json"
echo '{"cwd":"/test","version":"2.1.207","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000}}' |
    CLAUDE_PULSE_DEBUG_RATE_LIMITS=1 CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE="$diag_file3" "$PULSE" >/dev/null 2>&1
assert_contains "$(cat "$diag_file3" 2>/dev/null)" '"rate_limit_keys":[]' "diagnostic handles missing rate_limits object"

# Non-object rate_limits also degrades to an empty key list (jq `keys` on a
# string used to abort the write, silently skipping the capture)
diag_file4="$TEST_TMPDIR/rl-diag-nonobj.json"
echo '{"cwd":"/test","version":"2.1.207","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":1,"total_output_tokens":1,"context_window_size":200000},"rate_limits":"unexpected"}' |
    CLAUDE_PULSE_DEBUG_RATE_LIMITS=1 CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE="$diag_file4" "$PULSE" >/dev/null 2>&1
assert_contains "$(cat "$diag_file4" 2>/dev/null)" '"rate_limit_keys":[]' "diagnostic handles non-object rate_limits"

# --- Malformed rate_limits robustness ---
echo ""
echo "Testing malformed rate_limits robustness..."

# Regression: a scalar bucket value used to make the fable_rate scan index a
# number, aborting the ENTIRE jq extraction — model, cwd, and all rates
# blanked, not just the Fable segment.
out_scalar_sibling=$(run_pulse '{"rate_limits":{"five_hour":{"used_percentage":10},"weird_bucket":5}}')
assert_contains "$out_scalar_sibling" "Opus 4.6" "scalar sibling bucket does not blank model detection"
assert_contains "$out_scalar_sibling" "5h:10%" "scalar sibling bucket does not blank 5h rate"

# A scalar Fable bucket is a supported shape (percentage() handles numbers)
out_scalar_fable=$(run_pulse '{"rate_limits":{"seven_day_overage_included":96}}')
assert_contains "$out_scalar_fable" "Opus 4.6" "scalar Fable bucket does not blank model detection"
assert_contains "$out_scalar_fable" "Fable:" "scalar Fable bucket renders the Fable segment"
assert_contains "$out_scalar_fable" "96%" "scalar Fable bucket renders its percentage"

# rate_limits as a non-object degrades to no rate segments, not a blank line
out_rl_nonobj=$(run_pulse '{"rate_limits":"unexpected-string"}')
assert_contains "$out_rl_nonobj" "Opus 4.6" "non-object rate_limits does not blank the statusline"
assert_not_contains "$out_rl_nonobj" "5h:" "non-object rate_limits shows no rate segments"

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
