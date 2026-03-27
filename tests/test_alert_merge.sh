#!/bin/bash
# Tests for alert city merging logic (build_state accumulates cities across waves)

source "$(dirname "$0")/helpers.sh"
setup
setup_mock_daemon

echo "Testing alert city merging..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Extract build_state, write_state, and log from daemon for isolated testing
export STATE_FILE="$RED_ALERT_STATE_FILE"
export STATE_DIR="$TEST_TMPDIR"
export LOG_FILE="$TEST_TMPDIR/test.log"
eval "$(sed -n '/^write_state()/,/^}/p' "$SCRIPT_DIR/red-alert-daemon.sh")"
eval "$(sed -n '/^log()/,/^}/p' "$SCRIPT_DIR/red-alert-daemon.sh" | sed "s|\$LOG_FILE|$TEST_TMPDIR/test.log|")"
eval "$(sed -n '/^build_state()/,/^}/p' "$SCRIPT_DIR/red-alert-daemon.sh")"

now=$(date +%s)

# test_main_alert_merge: two missile waves for different areas merge cities
write_state "$(build_state "wave1" "1" "missiles" '["תל אביב"]' '["Tel Aviv"]' "$now" 0)"
sleep 1
now2=$(date +%s)
result=$(build_state "wave2" "1" "missiles" '["חיפה"]' '["Haifa"]' "$now2" 0)
# Result should contain both cities
assert_contains "$result" "Tel Aviv" "main merge: Tel Aviv preserved from wave1"
assert_contains "$result" "Haifa" "main merge: Haifa added from wave2"

# test_main_alert_no_merge_after_expiry: expired alert not merged
write_state "$(echo "$result" | jq '.display_until_unix = 1000')"
now3=$(date +%s)
result2=$(build_state "wave3" "1" "missiles" '["אשדוד"]' '["Ashdod"]' "$now3" 0)
assert_contains "$result2" "Ashdod" "no merge after expiry: Ashdod present"
assert_not_contains "$result2" "Tel Aviv" "no merge after expiry: Tel Aviv gone"

# test_same_alert_id_no_merge: same alert ID updates, doesn't duplicate
now4=$(date +%s)
write_state "$(build_state "alert1" "1" "missiles" '["תל אביב"]' '["Tel Aviv"]' "$now4" 0)"
result3=$(build_state "alert1" "1" "missiles" '["תל אביב"]' '["Tel Aviv"]' "$((now4+2))" 0)
tel_count=$(echo "$result3" | jq '[.cities_en[]? | select(. == "Tel Aviv")] | length')
assert_equals "$tel_count" "1" "same ID: no duplicate cities"

# test_pre_alert_merge: two pre-alert waves merge in pre_alert field
now5=$(date +%s)
# Set up a missile as main, then two pre-alerts
write_state "$(build_state "m1" "1" "missiles" '["מטולה"]' '["Metula"]' "$now5" 0)"
# First pre-alert for Ramla
write_state "$(build_state "pre1" "14" "pre" '["רמלה"]' '["Ramla"]' "$now5" 0)"
# Second pre-alert for Haifa (while first still has TTL)
result4=$(build_state "pre2" "14" "pre" '["חיפה"]' '["Haifa"]' "$((now5+5))" 0)
pre_cities=$(echo "$result4" | jq -r '.pre_alert.cities_en[]?' 2>/dev/null)
assert_contains "$pre_cities" "Ramla" "pre-alert merge: Ramla preserved"
assert_contains "$pre_cities" "Haifa" "pre-alert merge: Haifa added"

# test_pre_alert_as_main_merge: back-to-back pre-alerts as main alert merge
now6=$(date +%s)
rm -f "$STATE_FILE"
write_state "$(build_state "pa1" "14" "pre" '["רמלה"]' '["Ramla"]' "$now6" 0)"
result5=$(build_state "pa2" "14" "pre" '["חיפה"]' '["Haifa"]' "$((now6+5))" 0)
assert_contains "$result5" "Ramla" "pre-as-main merge: Ramla preserved"
assert_contains "$result5" "Haifa" "pre-as-main merge: Haifa added"

# test_different_category_no_merge: cat 1 then cat 6 don't merge
now7=$(date +%s)
write_state "$(build_state "miss1" "1" "missiles" '["תל אביב"]' '["Tel Aviv"]' "$now7" 0)"
result6=$(build_state "uav1" "6" "uav" '["מטולה"]' '["Metula"]' "$((now7+5))" 0)
assert_not_contains "$result6" "Tel Aviv" "diff category: cat 1 cities not merged into cat 6"
assert_contains "$result6" "Metula" "diff category: cat 6 cities present"

# test_pre_alert_survives_all_clear: pre_alert kept when main transitions to all-clear
now8=$(date +%s)
rm -f "$STATE_FILE"
# Set up: missile as main, pre_alert with active TTL
write_state "$(build_state "m2" "1" "missiles" '["מטולה"]' '["Metula"]' "$now8" 0)"
# Add a pre_alert by simulating the cat14-while-missile path
write_state "$(build_state "pre3" "14" "pre" '["תל אביב"]' '["Tel Aviv"]' "$now8" 0)"
# Now all-clear arrives — pre_alert should survive
result7=$(build_state "clear1" "13" "all clear" '[]' '[]' "$((now8+5))" "$((now8+5))")
pre_du=$(echo "$result7" | jq -r '.pre_alert.display_until_unix // 0')
assert_not_contains "$result7" '"pre_alert":null' "pre_alert survives all-clear while TTL active"

# test_pre_alert_dropped_after_expiry: expired pre_alert not carried into all-clear
now9=$(date +%s)
rm -f "$STATE_FILE"
write_state "$(build_state "m3" "1" "missiles" '["מטולה"]' '["Metula"]' "$now9" 0)"
# Write pre_alert with already-expired display_until
pre_expired=$(jq -n '{alert_id:"old_pre",cat:"14",title:"pre",cities:[],cities_en:[],last_seen_unix:1000,first_seen_unix:1000,display_until_unix:1001}')
write_state "$(jq --argjson pa "$pre_expired" '.pre_alert = $pa' "$STATE_FILE")"
result8=$(build_state "clear2" "13" "all clear" '[]' '[]' "$((now9+5))" "$((now9+5))")
pre_val=$(echo "$result8" | jq -r '.pre_alert')
assert_equals "$pre_val" "null" "expired pre_alert not carried into all-clear"

cleanup
report
