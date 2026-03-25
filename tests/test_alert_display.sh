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

# test_expired_alert: state older than 60s → shows listening, not alert
export RED_ALERT_MODE="all"
setup_expired_state "1" '["תל אביב"]'
output=$(run_pulse)
assert_not_contains "$output" "🚀" "expired alert not shown"
assert_contains "$output" "🟢" "expired alert shows daemon ON indicator"

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

cleanup
report
