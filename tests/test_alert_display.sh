#!/bin/bash
# Tests for Red Alert display in claude-pulse statusline

source "$(dirname "$0")/helpers.sh"
setup
setup_mock_daemon

echo "Testing alert display..."

# test_no_alert: no state file, no env vars → no alert in output
unset RED_ALERT_CITIES RED_ALERT_MODE
output=$(run_pulse)
assert_not_contains "$output" "🚀" "no alert without config"
assert_not_contains "$output" "MISSILES" "no MISSILES label without config"

# test_no_state_file: env set but no state file → normal output, no alert
export RED_ALERT_MODE="all"
rm -f "$RED_ALERT_STATE_FILE"
output=$(run_pulse)
assert_not_contains "$output" "🚀" "no alert without state file"
assert_contains "$output" "🧠" "normal output preserved without state file"

# test_active_alert: mock state with cat=1, 2 cities → alert line shown
export RED_ALERT_MODE="all"
setup_mock_state "1" '["תל אביב - מרכז העיר","רמת גן - מערב"]'
output=$(run_pulse)
assert_contains "$output" "🚀" "active alert shows rocket emoji"
assert_contains "$output" "MISSILES" "active alert shows MISSILES label"
assert_contains "$output" "תל אביב" "active alert shows Tel Aviv"
assert_contains "$output" "רמת גן" "active alert shows Ramat Gan"

# test_expired_alert: state older than 60s (no display_until) → shows listening
export RED_ALERT_MODE="all"
setup_expired_state "1" '["תל אביב"]'
output=$(run_pulse)
assert_not_contains "$output" "🚀" "expired alert not shown"
assert_contains "$output" "🟢" "expired alert shows daemon ON indicator"

# test_recent_alert: display_until passed but within 5 min → shows "Recent"
export RED_ALERT_MODE="all"
now=$(date +%s)
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"test_recent","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$((now-120)),"cleared_unix":0,"first_seen_unix":$((now-120)),"display_until_unix":$((now-10))}
EOF
output=$(run_pulse)
assert_contains "$output" "Recent" "recent alert shows Recent label"
assert_contains "$output" "🔴" "recent alert shows red dot"

# test_active_display_until: within display_until → shows red banner
export RED_ALERT_MODE="all"
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"test_active","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$((now-90)),"cleared_unix":0,"first_seen_unix":$((now-90)),"display_until_unix":$((now+90))}
EOF
output=$(run_pulse)
assert_contains "$output" "🚀" "display_until active shows rocket"
assert_contains "$output" "MISSILES" "display_until active shows MISSILES"

# test_priority: expired missile + active pre_alert → shows pre-alert, not recent missile
export RED_ALERT_MODE="all"
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"m1","cat":"1","title":"missiles","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$((now-200)),"cleared_unix":0,"first_seen_unix":$((now-200)),"display_until_unix":$((now-100)),"pre_alert":{"alert_id":"p1","cat":"14","title":"pre","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$((now-60)),"first_seen_unix":$((now-60)),"display_until_unix":$((now+120))}}
EOF
output=$(run_pulse)
assert_contains "$output" "Pre-alert" "priority: active pre-alert beats recent missile"
assert_not_contains "$output" "Recent" "priority: recent missile hidden by active pre-alert"

# test_pre_alert_fallback: main alert active but no city match, pre_alert matches
export RED_ALERT_CITIES="Tel Aviv"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"uav1","cat":"6","title":"t","cities":["מטולה"],"cities_en":["Metula"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120)),"pre_alert":{"alert_id":"p1","cat":"14","title":"pre","cities":["תל אביב - עבר הירקון"],"cities_en":["Tel Aviv - Across the Yarkon"],"last_seen_unix":$now,"first_seen_unix":$now,"display_until_unix":$((now+120))}}
EOF
output=$(run_pulse)
assert_contains "$output" "Pre-alert" "pre_alert fallback: shows pre-alert when main has no city match"
assert_not_contains "$output" "daemon ON" "pre_alert fallback: not showing daemon ON"

# test_city_filter: only matching cities shown
export RED_ALERT_CITIES="Tel Aviv"
unset RED_ALERT_MODE
# State has both Hebrew and English cities
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"test_123","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב - מרכז העיר","חיפה - כרמל"],"cities_en":["Tel Aviv - City Center","Haifa - Carmel"],"last_seen_unix":$(date +%s),"cleared_unix":0}
EOF
output=$(run_pulse)
assert_contains "$output" "Tel Aviv" "city filter: Tel Aviv shown"
assert_not_contains "$output" "Haifa" "city filter: Haifa filtered out"

# test_mode_all: all cities shown regardless of filter
export RED_ALERT_CITIES="Tel Aviv"
export RED_ALERT_MODE="all"
setup_mock_state "1" '["תל אביב - מרכז העיר","חיפה - כרמל"]'
output=$(run_pulse)
assert_contains "$output" "תל אביב" "mode all: Tel Aviv shown"
assert_contains "$output" "חיפה" "mode all: Haifa also shown"

# test_many_cities: >3 cities shows count
export RED_ALERT_MODE="all"
setup_mock_state "1" '["תל אביב","רמת גן","חיפה","אשדוד","אשקלון"]'
output=$(run_pulse)
assert_contains "$output" "5 cities" "many cities: shows count"

# test_alert_categories: each category shows correct icon
for pair in \
    "1:🚀:MISSILES" \
    "2:✈️:AIRCRAFT" \
    "3:🌍:EARTHQUAKE" \
    "4:🌊:TSUNAMI" \
    "7:🔫:INFILTRATION" \
    "13:✅:All clear" \
    "14:⚠️:Pre-alert" \
    "101:🔔:DRILL"; do
    cat_val="${pair%%:*}"
    rest="${pair#*:}"
    icon="${rest%%:*}"
    label="${rest##*:}"
    export RED_ALERT_MODE="all"
    if [[ "$cat_val" == "13" ]]; then
        # All clear has 15s window
        setup_mock_state "$cat_val" '[]' "הקלה"
    elif [[ "$cat_val" == "14" ]]; then
        # Pre-alert
        setup_mock_state "$cat_val" '[]' "התרעה מוקדמת"
    else
        setup_mock_state "$cat_val" '["תל אביב"]'
    fi
    output=$(run_pulse)
    assert_contains "$output" "$label" "category $cat_val: shows $label"
done

# test_red_background: alert line uses red background ANSI code
export RED_ALERT_MODE="all"
setup_mock_state "1" '["תל אביב"]'
output=$(run_pulse)
assert_contains "$output" "[41;97m" "alert has red background ANSI"

# test_priority_active_main_beats_pre: active missile with city match beats active pre-alert
export RED_ALERT_CITIES="Tel Aviv"
unset RED_ALERT_MODE
now=$(date +%s)
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"m1","cat":"1","title":"missiles","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120)),"pre_alert":{"alert_id":"p1","cat":"14","title":"pre","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$now,"first_seen_unix":$now,"display_until_unix":$((now+120))}}
EOF
output=$(run_pulse)
assert_contains "$output" "MISSILES" "priority matrix: active missile beats active pre-alert"
assert_not_contains "$output" "Pre-alert" "priority matrix: pre-alert hidden by active missile"

# test_priority_pre_beats_no_match_main: active pre-alert shown when main has no city match
export RED_ALERT_CITIES="Tel Aviv"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"m2","cat":"1","title":"missiles","cities":["מטולה"],"cities_en":["Metula"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120)),"pre_alert":{"alert_id":"p2","cat":"14","title":"pre","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$now,"first_seen_unix":$now,"display_until_unix":$((now+120))}}
EOF
output=$(run_pulse)
assert_contains "$output" "Pre-alert" "priority matrix: pre-alert shown when main no city match"

# test_global_cat13: all-clear shows without city filter
export RED_ALERT_CITIES="Tel Aviv"
unset RED_ALERT_MODE
setup_mock_state "13" '[]' "הקלה"
output=$(run_pulse)
assert_contains "$output" "All clear" "global cat: all-clear shows without city filter"

cleanup
report
