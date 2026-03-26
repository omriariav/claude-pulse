#!/bin/bash
# Tests for city filtering logic (filter_alert_cities function)

source "$(dirname "$0")/helpers.sh"
setup
setup_mock_daemon

echo "Testing city filtering..."

now=$(date +%s)

# test_hebrew_mapping: English filter matches via Hebrew→English mapping
export RED_ALERT_CITIES="Tel Aviv"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"t1","cat":"1","title":"t","cities":["תל אביב - יפו"],"cities_en":["Tel Aviv - Jaffa"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120))}
EOF
output=$(run_pulse)
assert_contains "$output" "Tel Aviv" "Hebrew mapping: English filter matches Hebrew city"

# test_direct_hebrew_filter: Hebrew text as filter matches Hebrew city
export RED_ALERT_CITIES="רמלה"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"t2","cat":"1","title":"t","cities":["רמלה"],"cities_en":["Ramla"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120))}
EOF
output=$(run_pulse)
assert_contains "$output" "Ramla" "Direct Hebrew filter: Hebrew text matches Hebrew city"

# test_english_fuzzy: partial English substring matches
export RED_ALERT_CITIES="Across the Yarkon"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"t3","cat":"1","title":"t","cities":["תל אביב - עבר הירקון"],"cities_en":["Tel Aviv - Across the Yarkon"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120))}
EOF
output=$(run_pulse)
assert_contains "$output" "Across the Yarkon" "English fuzzy: partial substring matches"

# test_no_match: unrelated filter shows no alert
export RED_ALERT_CITIES="Eilat"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"t4","cat":"1","title":"t","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120))}
EOF
output=$(run_pulse)
assert_not_contains "$output" "MISSILES" "No match: unrelated city filter hides alert"
assert_not_contains "$output" "Tel Aviv" "No match: unrelated filter hides cities"

# test_pre_alert_fallback_hebrew: main has no city match, pre_alert matches via Hebrew mapping
# This is the regression test for issue #16
export RED_ALERT_CITIES="Tel Aviv"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"uav1","cat":"6","title":"t","cities":["מטולה"],"cities_en":["Metula"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120)),"pre_alert":{"alert_id":"p1","cat":"14","title":"pre","cities":["תל אביב - עבר הירקון"],"cities_en":["Tel Aviv - Across the Yarkon"],"last_seen_unix":$now,"first_seen_unix":$now,"display_until_unix":$((now+120))}}
EOF
output=$(run_pulse)
assert_contains "$output" "Pre-alert" "Pre-alert fallback Hebrew: shows pre-alert when main filtered out (#16)"
assert_not_contains "$output" "UAV" "Pre-alert fallback Hebrew: UAV hidden when no city match"

# test_multiple_filters: comma-separated filters match different cities
export RED_ALERT_CITIES="Tel Aviv,Haifa"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"t5","cat":"1","title":"t","cities":["תל אביב","חיפה","אשדוד"],"cities_en":["Tel Aviv","Haifa","Ashdod"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120))}
EOF
output=$(run_pulse)
assert_contains "$output" "Tel Aviv" "Multiple filters: Tel Aviv matched"
assert_contains "$output" "Haifa" "Multiple filters: Haifa matched"
assert_not_contains "$output" "Ashdod" "Multiple filters: Ashdod filtered out"

# test_case_insensitive: filter is case-insensitive
export RED_ALERT_CITIES="tel AVIV"
unset RED_ALERT_MODE
cat > "$RED_ALERT_STATE_FILE" <<EOF
{"alert_id":"t6","cat":"1","title":"t","cities":["תל אביב"],"cities_en":["Tel Aviv"],"last_seen_unix":$now,"cleared_unix":0,"first_seen_unix":$now,"display_until_unix":$((now+120))}
EOF
output=$(run_pulse)
assert_contains "$output" "Tel Aviv" "Case insensitive: mixed-case filter matches"

cleanup
report
