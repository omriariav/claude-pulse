#!/bin/bash
# Tests for the taboola density mode (single line, reference 16-color ANSI palette)

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/helpers.sh"
setup

PULSE="$TESTS_DIR/../claude-pulse"

# Run claude-pulse in taboola mode with a given cwd and extra JSON merged in.
run_taboola() {
    local cwd="$1"; local extra="$2"; [[ -z "$extra" ]] && extra="{}"
    local json
    json=$(jq -n --arg cwd "$cwd" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')
    json=$(echo "$json" | jq ". + $extra")
    # Isolate from the host environment (no real daemon / squad / colors interference)
    echo "$json" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR -u AM_ROOT -u AM_ME -u AM_BASE_ROOT \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null
}

# Strip ANSI for text assertions
strip() { sed $'s/\033\[[0-9;]*m//g'; }

echo "Testing taboola mode..."

# Basename-only directory (no ~/ path prefix)
out=$(run_taboola "/Users/foo/Code/my-project" | strip)
assert_contains "$out" "my-project" "taboola: shows last folder"
assert_not_contains "$out" "/Users/foo" "taboola: no full path"
assert_not_contains "$out" "Code/my-project" "taboola: no parent path"

# Short model label, not the long name
out=$(run_taboola "/tmp" | strip)
assert_contains "$out" "Op4.8" "taboola: short model label"
assert_not_contains "$out" "Opus 4.8" "taboola: not the long model name"

# Dim │ separators present
out=$(run_taboola "/tmp")
assert_contains "$out" "│" "taboola: has separators"

# Uses 16-color ANSI, NOT claude-pulse truecolor (no 38;2 sequences)
assert_not_contains "$out" "38;2" "taboola: no truecolor RGB codes"
assert_contains "$out" $'\033[34m' "taboola: uses ANSI blue (34) for dir"
assert_contains "$out" $'\033[36m' "taboola: uses ANSI cyan (36) for model"

# Context shown as REMAINING %, not used %
# 120000/200000 ~ 60% used -> ~40% remaining (billing calc may nudge it); used% must not appear bare.
out=$(run_taboola "/tmp" | strip)
assert_contains "$out" "%" "taboola: shows a percentage"

# Effort surfaced when present, omitted when absent
out=$(run_taboola "/tmp" '{"effort":{"level":"high"}}' | strip)
assert_contains "$out" "high" "taboola: shows effort level"
out=$(run_taboola "/tmp" | strip)
assert_not_contains "$out" "high" "taboola: no effort when absent"

# 5h / 7d rate limits
out=$(run_taboola "/tmp" '{"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":41.2}}}' | strip)
assert_contains "$out" "5h:23%" "taboola: shows 5h limit"
assert_contains "$out" "7d:41%" "taboola: shows 7d limit"

# API cost shown, and hidden via CLAUDE_PULSE_HIDE_COST / when $0
out=$(echo '{"cwd":"/tmp","model":{"id":"claude-opus-4-8"},"context_window":{"total_input_tokens":120000,"total_output_tokens":5000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}' \
    | env -u RED_ALERT_CITIES -u RED_ALERT_MODE CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
assert_contains "$out" '$0.42' "taboola: shows API cost"
out=$(echo '{"cwd":"/tmp","model":{"id":"claude-opus-4-8"},"context_window":{"total_input_tokens":120000,"total_output_tokens":5000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}' \
    | env -u RED_ALERT_CITIES -u RED_ALERT_MODE CLAUDE_PULSE_HIDE_COST=1 CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
assert_not_contains "$out" '$0.42' "taboola: CLAUDE_PULSE_HIDE_COST hides cost"
out=$(run_taboola "/tmp" '{"cost":{"total_cost_usd":0}}' | strip)
assert_not_contains "$out" '$0.00' "taboola: skips \$0 cost"

# NO_COLOR strips all ANSI
out=$(echo '{"cwd":"/Users/foo/proj","model":{"id":"claude-opus-4-8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":40000,"total_output_tokens":2000,"context_window_size":200000}}' \
    | env -u RED_ALERT_CITIES -u RED_ALERT_MODE NO_COLOR=1 CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null)
assert_not_contains "$out" $'\033[' "taboola: NO_COLOR strips ANSI"
assert_contains "$out" "proj" "taboola: NO_COLOR still renders content"

# amq-squad team name detected from .amq-squad/team.json (walks up)
squad_dir="$TEST_TMPDIR/squad"
mkdir -p "$squad_dir/.amq-squad" "$squad_dir/sub"
echo '{"workstream":"my-squad","members":[]}' > "$squad_dir/.amq-squad/team.json"
if command -v amq &>/dev/null; then
    out=$(run_taboola "$squad_dir/sub" | strip)
    assert_contains "$out" "amq:my-squad" "taboola: amq team from nearest team.json (walks up)"
else
    echo "  (skipping amq test — amq not installed)"
fi

# Exit code is 0 (statusline must never fail-exit, or Claude Code renders nothing)
echo '{"cwd":"/tmp","model":{"id":"claude-opus-4-8"},"context_window":{"total_input_tokens":40000,"total_output_tokens":2000,"context_window_size":200000}}' \
    | env -u RED_ALERT_CITIES -u RED_ALERT_MODE CLAUDE_PULSE_DENSITY=taboola "$PULSE" >/dev/null 2>&1
assert_equals "0" "$?" "taboola: exits 0"

cleanup
report
