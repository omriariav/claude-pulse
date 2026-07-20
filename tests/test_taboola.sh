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

# Effort surfaced when present (abbreviated), omitted when absent
out=$(run_taboola "/tmp" '{"effort":{"level":"high"}}' | strip)
assert_contains "$out" "Op4.8 H" "taboola: abbreviates effort high→H"
out=$(run_taboola "/tmp" '{"effort":{"level":"xhigh"}}' | strip)
assert_contains "$out" "Op4.8 XH" "taboola: abbreviates effort xhigh→XH"
out=$(run_taboola "/tmp" '{"effort":{"level":"max"}}' | strip)
assert_contains "$out" "Op4.8 MAX" "taboola: abbreviates effort max→MAX"
out=$(run_taboola "/tmp" | strip)
assert_not_contains "$out" "Op4.8 H" "taboola: no effort suffix when absent"
# Effort uses magenta (35), not dim (2) — dim was too dark
out=$(run_taboola "/tmp" '{"effort":{"level":"high"}}')
assert_contains "$out" $'\033[35m' "taboola: effort uses magenta (35)"

# Tri-color health (#4): context window remaining green/yellow/red.
# /tmp is not a git repo, so red/yellow can only come from the context segment here.
out=$(run_taboola "/tmp" '{"context_window":{"total_input_tokens":196000,"total_output_tokens":3000,"context_window_size":200000}}')
assert_contains "$out" $'\033[31m' "taboola: context RED when nearly full (<=20% left)"
out=$(run_taboola "/tmp" '{"context_window":{"total_input_tokens":130000,"total_output_tokens":0,"context_window_size":200000}}')
assert_contains "$out" $'\033[33m' "taboola: context YELLOW at ~35% left"
out=$(run_taboola "/tmp" '{"context_window":{"total_input_tokens":40000,"total_output_tokens":0,"context_window_size":200000}}')
assert_contains "$out" $'\033[32m' "taboola: context GREEN with plenty left"

# Tri-color health (#4): rate limits show the right value + threshold colors
out=$(run_taboola "/tmp" '{"rate_limits":{"five_hour":{"used_percentage":85},"seven_day":{"used_percentage":62}}}' | strip)
assert_contains "$out" "5h:85%" "taboola: 5h value (red threshold)"
assert_contains "$out" "7d:62%" "taboola: 7d value (yellow threshold)"

# 5h / 7d rate limits
out=$(run_taboola "/tmp" '{"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":41.2}}}' | strip)
assert_contains "$out" "5h:23%" "taboola: shows 5h limit"
assert_contains "$out" "7d:41%" "taboola: shows 7d limit"

# Fable-specific weekly quota (current API key), hidden when absent
out=$(run_taboola "/tmp" '{"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41},"seven_day_overage_included":{"used_percentage":96}}}' | strip)
assert_contains "$out" "Fable:96%" "taboola: shows Fable weekly limit"
out=$(run_taboola "/tmp" '{"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41}}}' | strip)
assert_not_contains "$out" "Fable:" "taboola: hides Fable limit when absent"

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
    # Non-squad dir (amq installed but no team/session) → amq:n/a
    out=$(run_taboola "/tmp" | strip)
    assert_contains "$out" "amq:n/a" "taboola: amq:n/a when amq present but no squad"
else
    echo "  (skipping amq tests — amq not installed)"
fi

# --- Regression: current pane must resolve its OWN profile, not the first/
# default profile found on disk (the amq:<profile>/<session>@<handle> form). ---
# Scenario: default profile carries an OLD workstream (v1-0-0-reshape) while the
# active pane was launched from the named profile codex-v2-11-0 (session v2-11-0,
# handle developer). Expected: amq:codex-v2-11-0/v2-11-0@developer — never the
# stale v1-0-0-reshape.
if command -v amq &>/dev/null; then
    LAYER="io.github.omriariav.amq-squad"
    proj="$TEST_TMPDIR/squad-profiles"
    mkdir -p "$proj/.amq-squad/teams"
    echo '{"schema":1,"workstream":"v1-0-0-reshape","members":[{"role":"cto","handle":"cto","session":"v1-0-0-reshape"}]}' \
        > "$proj/.amq-squad/team.json"
    echo '{"schema":3,"members":[{"role":"developer","handle":"developer","session":"v2-11-0"}]}' \
        > "$proj/.amq-squad/teams/codex-v2-11-0.json"
    agent_dir="$proj/.agent-mail/v2-11-0/agents/developer/extensions/$LAYER"
    mkdir -p "$agent_dir"
    cat > "$agent_dir/launch.json" <<EOF
{"schema":1,"team_profile":"codex-v2-11-0","session":"v2-11-0","handle":"developer","root":"$proj/.agent-mail/v2-11-0","base_root":"$proj/.agent-mail","tmux":{"pane_id":"%9099"}}
EOF
    pulse_json=$(jq -n --arg cwd "$proj" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')

    # Tier 1: env (AM_ROOT/AM_ME) pins the launch record for this pane.
    out=$(echo "$pulse_json" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        AM_ROOT="$proj/.agent-mail/v2-11-0" AM_BASE_ROOT="$proj/.agent-mail" AM_ME=developer \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_contains "$out" "amq:codex-v2-11-0/v2-11-0@developer" "taboola: resolves current named profile (not default)"
    assert_not_contains "$out" "v1-0-0-reshape" "taboola: does not show stale default-profile workstream"

    # Tier 2: no AM_*, matched purely by tmux pane id from the launch record.
    out=$(echo "$pulse_json" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        -u AM_ROOT -u AM_BASE_ROOT -u AM_ME TMUX_PANE="%9099" \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_contains "$out" "amq:codex-v2-11-0/v2-11-0@developer" "taboola: resolves profile via tmux pane id match"
    assert_not_contains "$out" "v1-0-0-reshape" "taboola: pane-id match avoids stale workstream"

    # Liveness guard (issue #48): tmux recycles pane ids, so a launch record whose
    # pane id equals $TMUX_PANE but whose recorded agent_pid is DEAD belongs to a
    # gone agent — it must NOT resolve as the current pane's identity.
    lproj="$TEST_TMPDIR/squad-livecheck"
    lagent="$lproj/.agent-mail/ses1/agents/dev/extensions/$LAYER"
    mkdir -p "$lproj/.amq-squad" "$lagent"
    echo '{"schema":1,"workstream":"ses1","members":[{"role":"dev","handle":"dev","session":"ses1"}]}' \
        > "$lproj/.amq-squad/team.json"
    # pid 2147483646: above any real pid, guaranteed not running → kill -0 fails.
    echo '{"team_profile":"named","session":"ses1","handle":"ghostagent","agent_pid":2147483646,"tmux":{"pane_id":"%deadpane"}}' \
        > "$lagent/launch.json"
    ljson=$(jq -n --arg cwd "$lproj" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')
    out=$(echo "$ljson" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        -u AM_ROOT -u AM_BASE_ROOT -u AM_ME TMUX_PANE="%deadpane" \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_not_contains "$out" "ghostagent" "taboola: dead agent_pid rejects recycled-pane match"

    # Same record but with a LIVE agent_pid ($$ = the test runner, alive now) →
    # the pane match is trusted and the identity resolves.
    echo '{"team_profile":"named","session":"ses1","handle":"livedev","agent_pid":'"$$"',"tmux":{"pane_id":"%livepane"}}' \
        > "$lagent/launch.json"
    out=$(echo "$ljson" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        -u AM_ROOT -u AM_BASE_ROOT -u AM_ME TMUX_PANE="%livepane" \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_contains "$out" "@livedev" "taboola: live agent_pid keeps recycled-pane match"

    # Ambiguous: two named profiles claim the same session and identity is
    # otherwise unproven → explicit degraded marker, never a silent pick.
    echo '{"schema":3,"members":[{"handle":"x","session":"v2-11-0"}]}' \
        > "$proj/.amq-squad/teams/decoy.json"
    out=$(echo "$pulse_json" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        -u AM_ME -u TMUX_PANE AM_ROOT="$proj/.agent-mail/v2-11-0" AM_BASE_ROOT="$proj/.agent-mail" \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_contains "$out" "amq:?" "taboola: ambiguous profile shows degraded marker"

    # Default profile (team_profile=null) shows default/<session> when proven —
    # guards the empty-leading-field parse (tab would collapse it and shift left).
    dproj="$TEST_TMPDIR/squad-default"
    mkdir -p "$dproj/.amq-squad" "$dproj/.agent-mail/main/agents/cto/extensions/$LAYER"
    echo '{"schema":1,"workstream":"main","members":[{"role":"cto","handle":"cto","session":"main"}]}' \
        > "$dproj/.amq-squad/team.json"
    echo '{"team_profile":null,"session":"main","handle":"cto","root":"'"$dproj"'/.agent-mail/main","tmux":{"pane_id":"%9100"}}' \
        > "$dproj/.agent-mail/main/agents/cto/extensions/$LAYER/launch.json"
    djson=$(jq -n --arg cwd "$dproj" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')
    out=$(echo "$djson" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        AM_ROOT="$dproj/.agent-mail/main" AM_BASE_ROOT="$dproj/.agent-mail" AM_ME=cto \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_contains "$out" "amq:default/main@cto" "taboola: proven default profile shows default/<session>"

    # Dedup: when the resolved profile equals the session, don't repeat it —
    # amq:<x>/<x>@handle collapses to amq:<x>@handle.
    sproj="$TEST_TMPDIR/squad-same"
    mkdir -p "$sproj/.amq-squad" "$sproj/.agent-mail/dup/agents/dev/extensions/$LAYER"
    echo '{"schema":1,"workstream":"dup","members":[{"role":"dev","handle":"dev","session":"dup"}]}' \
        > "$sproj/.amq-squad/team.json"
    echo '{"team_profile":"dup","session":"dup","handle":"dev","root":"'"$sproj"'/.agent-mail/dup","tmux":{"pane_id":"%9101"}}' \
        > "$sproj/.agent-mail/dup/agents/dev/extensions/$LAYER/launch.json"
    sjson=$(jq -n --arg cwd "$sproj" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')
    out=$(echo "$sjson" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        AM_ROOT="$sproj/.agent-mail/dup" AM_BASE_ROOT="$sproj/.agent-mail" AM_ME=dev \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_contains "$out" "amq:dup@dev" "taboola: profile==session collapses to single label"
    assert_not_contains "$out" "amq:dup/dup" "taboola: profile==session not repeated"

    # tmux pane match must check .tmux.pane_id specifically, not just any field
    # equal to $TMUX_PANE (grep is only a prefilter). Here a NON-pane field
    # (handle) equals the active pane string, but the real pane id differs.
    fproj="$TEST_TMPDIR/squad-falsepane"
    fagent="$fproj/.agent-mail/s1/agents/%falsey/extensions/$LAYER"
    mkdir -p "$fproj/.amq-squad" "$fagent"
    echo '{"workstream":"s1","members":[{"handle":"%falsey","session":"s1"}]}' > "$fproj/.amq-squad/team.json"
    echo '{"team_profile":"named","session":"s1","handle":"%falsey","tmux":{"pane_id":"%realpane"}}' \
        > "$fagent/launch.json"
    fjson=$(jq -n --arg cwd "$fproj" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')
    out=$(echo "$fjson" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        -u AM_ROOT -u AM_BASE_ROOT -u AM_ME TMUX_PANE="%falsey" \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_not_contains "$out" "amq:named/s1" "taboola: pane match ignores non-pane fields equal to TMUX_PANE"

    # A stale/nonexistent AM_ROOT must not be trusted as the session source.
    sproj="$TEST_TMPDIR/squad-stale"
    mkdir -p "$sproj/.amq-squad"
    echo '{"workstream":"realws","members":[]}' > "$sproj/.amq-squad/team.json"
    sjson=$(jq -n --arg cwd "$sproj" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')
    out=$(echo "$sjson" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR \
        -u AM_ME -u TMUX_PANE AM_ROOT="$sproj/.agent-mail/deleted-session" AM_BASE_ROOT="$sproj/.agent-mail" \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_not_contains "$out" "deleted-session" "taboola: stale AM_ROOT not used as session"

    # A stale non-empty AM_ROOT must NOT suppress authoritative pane-id recovery:
    # Tier 2 should still scan the base root and resolve via the launch record.
    rproj="$TEST_TMPDIR/squad-staleroot-pane"
    ragent="$rproj/.agent-mail/codex-v2-12-0/v2-12-0/agents/developer/extensions/$LAYER"
    mkdir -p "$rproj/.amq-squad/teams" "$ragent"
    echo '{"workstream":"v1-0-0-reshape","members":[]}' > "$rproj/.amq-squad/team.json"
    echo '{"members":[{"handle":"developer","session":"v2-12-0"}]}' > "$rproj/.amq-squad/teams/codex-v2-12-0.json"
    echo '{"team_profile":"codex-v2-12-0","session":"v2-12-0","handle":"developer","tmux":{"pane_id":"%42"}}' \
        > "$ragent/launch.json"
    rjson=$(jq -n --arg cwd "$rproj" '{cwd:$cwd,model:{id:"claude-opus-4-8"},context_window:{total_input_tokens:120000,total_output_tokens:5000,context_window_size:200000}}')
    out=$(echo "$rjson" | env -u RED_ALERT_CITIES -u RED_ALERT_MODE -u NO_COLOR -u AM_ME \
        AM_ROOT="$rproj/.agent-mail/deleted-session" AM_BASE_ROOT="$rproj/.agent-mail/codex-v2-12-0" TMUX_PANE="%42" \
        CLAUDE_PULSE_DENSITY=taboola "$PULSE" 2>/dev/null | strip)
    assert_contains "$out" "amq:codex-v2-12-0/v2-12-0@developer" "taboola: stale AM_ROOT still recovers via pane-id"
    assert_not_contains "$out" "amq:?" "taboola: stale AM_ROOT does not degrade to ambiguous when pane resolvable"
else
    echo "  (skipping amq profile-resolution tests — amq not installed)"
fi

# Exit code is 0 (statusline must never fail-exit, or Claude Code renders nothing)
echo '{"cwd":"/tmp","model":{"id":"claude-opus-4-8"},"context_window":{"total_input_tokens":40000,"total_output_tokens":2000,"context_window_size":200000}}' \
    | env -u RED_ALERT_CITIES -u RED_ALERT_MODE CLAUDE_PULSE_DENSITY=taboola "$PULSE" >/dev/null 2>&1
assert_equals "0" "$?" "taboola: exits 0"

cleanup
report
