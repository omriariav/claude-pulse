#!/bin/bash
# red-alert-daemon.sh v3.2.0: Background daemon for Pikud HaOref alert monitoring
# Polls the official alert API every 2 seconds and writes state to disk
# Supports: normal mode (API), all mode (API, no filter), mock mode (offline testing)

STATE_DIR="${RED_ALERT_STATE_DIR:-$HOME/.local/state/claude-pulse}"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE_FILE="${STATE_DIR}/red_alert_state.json"
PID_FILE="${STATE_DIR}/red_alert_daemon.pid"
LOG_FILE="${STATE_DIR}/red_alert_daemon.log"
VERSION_FILE="${STATE_DIR}/daemon_version"
DAEMON_VERSION=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "$0" 2>/dev/null)
POLL_INTERVAL="${RED_ALERT_POLL_INTERVAL:-2}"
API_URL="https://www.oref.org.il/warningMessages/alert/alerts.json"

# Mock data for testing (cycles through these)
MOCK_SCENARIOS=(
    '{"cat":"1","title":"ירי רקטות וטילים","data":["תל אביב - מרכז העיר","רמת גן - מערב"]}'
    '{"cat":"2","title":"חדירת כלי טיס עוין","data":["חיפה - כרמל","חיפה - מפרץ"]}'
    '{}'
    '{"cat":"3","title":"רעידת אדמה","data":["אילת"]}'
    '{"cat":"1","title":"ירי רקטות וטילים","data":["אשדוד","אשקלון","באר שבע","נתניה","הרצליה"]}'
    '{}'
)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOUND_DIR="${RED_ALERT_SOUND_DIR:-$SCRIPT_DIR/static}"
DISTRICTS_FILE="${RED_ALERT_DISTRICTS_FILE:-$HOME/.claude/districts_eng.json}"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

cleanup() {
    log "Daemon stopping (PID $$)"
    # Only remove PID/version files and lock if they're ours
    current_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [[ "$current_pid" == "$$" ]]; then
        rm -f "$PID_FILE" "$VERSION_FILE"
        rm -rf "${STATE_DIR}/daemon.lock"
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# Write state atomically (temp file + rename)
write_state() {
    local tmp_file="${STATE_FILE}.$$"
    echo "$1" > "$tmp_file"
    mv -f "$tmp_file" "$STATE_FILE"
}

# Detect Pikud HaOref resolution titles ("threat removed/ended/cancelled/ruled out")
# These arrive under cat=14 (or cat=10) and mean the OPPOSITE of "be prepared".
is_resolution_title() {
    local title="$1"
    [[ "$title" =~ (הוסר|הוסרה|הוסרו|הסתיים|הסתיימה|הסתיימו|בוטל|בוטלה|בוטלו|נשלל|נשללה|נשללו|אין\ חשש) ]]
}

# Build state JSON safely using jq (handles quotes/escapes in API data)
build_state() {
    local id="$1" cat="$2" title="$3" cities="$4" cities_en="$5" last_seen="$6" cleared="$7"
    # Determine first_seen: keep existing if same alert, otherwise use last_seen
    local first_seen="$last_seen"
    if [[ -f "$STATE_FILE" ]]; then
        local prev_id prev_first
        prev_id=$(jq -r '.alert_id // ""' "$STATE_FILE" 2>/dev/null)
        prev_first=$(jq -r '.first_seen_unix // 0' "$STATE_FILE" 2>/dev/null)
        if [[ "$prev_id" == "$id" ]] && [[ "$prev_first" != "0" ]] && [[ "$prev_first" != "null" ]]; then
            first_seen="$prev_first"
            # Preserve accumulated cities from prior merges (re-poll of same ID must not lose them)
            local _prev_du _now_main
            _prev_du=$(jq -r '.display_until_unix // 0' "$STATE_FILE" 2>/dev/null)
            _now_main=$(date +%s)
            if [[ "$_prev_du" != "0" ]] && (( _prev_du >= _now_main )); then
                cities=$(jq -s '.[0] + .[1] | unique' <(echo "$cities") <(jq '.cities // []' "$STATE_FILE") 2>/dev/null)
                cities_en=$(jq -s '.[0] + .[1] | unique' <(echo "$cities_en") <(jq '.cities_en // []' "$STATE_FILE") 2>/dev/null)
            fi
        fi
    fi
    # Display until: max(last_seen + 60, first_seen + 180) for active alerts
    local display_until=0
    if [[ "$cleared" == "0" ]] && [[ -n "$cat" ]] && [[ "$cat" != "" ]]; then
        local opt1=$(( last_seen + 60 ))
        local opt2=$(( first_seen + 180 ))
        display_until=$(( opt1 > opt2 ? opt1 : opt2 ))
    fi
    # Merge cities with existing main alert if same category and TTL still active
    # Different alert waves for different areas should accumulate, not replace
    if [[ -f "$STATE_FILE" ]] && [[ "$cleared" == "0" ]] && [[ -n "$cat" ]]; then
        local prev_cat prev_du
        prev_cat=$(jq -r '.cat // ""' "$STATE_FILE" 2>/dev/null)
        prev_du=$(jq -r '.display_until_unix // 0' "$STATE_FILE" 2>/dev/null)
        local now_merge
        now_merge=$(date +%s)
        if [[ "$prev_cat" == "$cat" ]] && [[ "$prev_id" != "$id" ]] && [[ "$prev_du" != "0" ]] && (( prev_du > now_merge )); then
            cities=$(jq -s '.[0] + .[1] | unique' <(echo "$cities") <(jq '.cities // []' "$STATE_FILE") 2>/dev/null)
            cities_en=$(jq -s '.[0] + .[1] | unique' <(echo "$cities_en") <(jq '.cities_en // []' "$STATE_FILE") 2>/dev/null)
            # Keep earlier first_seen for longer display window
            if [[ "$prev_first" != "0" ]] && [[ "$prev_first" != "null" ]] && (( prev_first < first_seen )); then
                first_seen="$prev_first"
            fi
            # Recalculate display_until with merged first_seen
            opt2=$(( first_seen + 180 ))
            display_until=$(( opt1 > opt2 ? opt1 : opt2 ))
            # Keep later display_until
            if (( prev_du > display_until )); then
                display_until="$prev_du"
            fi
            log "ALERT MERGE: combined ${id} with existing ${prev_id} (cat=${cat})"
        fi
    fi
    # Handle pre_alert coexistence:
    # - Missile/UAV (1/2/6) overwriting pre-alert → save pre-alert in pre_alert field
    # - Pre-alert arriving while missile is active → store in pre_alert, keep missile as main
    local pre_alert="null"
    if [[ -f "$STATE_FILE" ]]; then
        local prev_cat
        prev_cat=$(jq -r '.cat // ""' "$STATE_FILE" 2>/dev/null)
        if [[ "$cat" == "14" ]] && [[ "$prev_cat" =~ ^(1|2|6)$ ]]; then
            # Pre-alert arriving while missile/UAV is main → don't overwrite, store as pre_alert
            # Preserve first_seen if same pre-alert ID already stored
            local pre_first_seen="$first_seen"
            local existing_pre_id
            existing_pre_id=$(jq -r '.pre_alert.alert_id // ""' "$STATE_FILE" 2>/dev/null)
            if [[ "$existing_pre_id" == "$id" ]]; then
                local existing_pre_first existing_pre_du_early
                existing_pre_first=$(jq -r '.pre_alert.first_seen_unix // 0' "$STATE_FILE" 2>/dev/null)
                existing_pre_du_early=$(jq -r '.pre_alert.display_until_unix // 0' "$STATE_FILE" 2>/dev/null)
                if [[ "$existing_pre_first" != "0" ]] && [[ "$existing_pre_first" != "null" ]]; then
                    pre_first_seen="$existing_pre_first"
                fi
                # Preserve accumulated cities from prior merges (re-poll of same ID must not lose them)
                local _now_early
                _now_early=$(date +%s)
                if [[ "$existing_pre_du_early" != "0" ]] && (( existing_pre_du_early >= _now_early )); then
                    cities=$(jq -s '.[0] + .[1] | unique' <(echo "$cities") <(jq -c '.pre_alert.cities // []' "$STATE_FILE") 2>/dev/null)
                    cities_en=$(jq -s '.[0] + .[1] | unique' <(echo "$cities_en") <(jq -c '.pre_alert.cities_en // []' "$STATE_FILE") 2>/dev/null)
                fi
            fi
            local pre_display_until
            local p_opt1=$(( last_seen + 60 ))
            local p_opt2=$(( pre_first_seen + 180 ))
            pre_display_until=$(( p_opt1 > p_opt2 ? p_opt1 : p_opt2 ))
            # Merge with existing pre_alert if its TTL is still active (different areas accumulate)
            local merged_cities="$cities"
            local merged_cities_en="$cities_en"
            local existing_pre_du
            existing_pre_du=$(jq -r '.pre_alert.display_until_unix // 0' "$STATE_FILE" 2>/dev/null)
            local now_merge
            now_merge=$(date +%s)
            if [[ "$existing_pre_du" != "0" ]] && (( existing_pre_du > now_merge )) && [[ "$existing_pre_id" != "$id" ]]; then
                # Existing pre_alert still active and different ID — merge cities (union)
                merged_cities=$(jq -s '.[0] + .[1] | unique' <(echo "$cities") <(jq '.pre_alert.cities // []' "$STATE_FILE") 2>/dev/null)
                merged_cities_en=$(jq -s '.[0] + .[1] | unique' <(echo "$cities_en") <(jq '.pre_alert.cities_en // []' "$STATE_FILE") 2>/dev/null)
                # Keep earlier first_seen for longer display
                local existing_pre_fs
                existing_pre_fs=$(jq -r '.pre_alert.first_seen_unix // 0' "$STATE_FILE" 2>/dev/null)
                if [[ "$existing_pre_fs" != "0" ]] && (( existing_pre_fs < pre_first_seen )); then
                    pre_first_seen="$existing_pre_fs"
                    p_opt2=$(( pre_first_seen + 180 ))
                    pre_display_until=$(( p_opt1 > p_opt2 ? p_opt1 : p_opt2 ))
                fi
                # Keep later display_until
                if (( existing_pre_du > pre_display_until )); then
                    pre_display_until="$existing_pre_du"
                fi
                log "PRE-ALERT MERGE: combined ${id} with existing ${existing_pre_id}"
            fi
            local pre_obj
            pre_obj=$(jq -n --arg id "$id" --arg cat "$cat" --arg title "$title" \
                --argjson cities "$merged_cities" --argjson cities_en "$merged_cities_en" \
                --argjson last_seen "$last_seen" --argjson first_seen "$pre_first_seen" \
                --argjson display_until "$pre_display_until" \
                '{alert_id:$id,cat:$cat,title:$title,cities:$cities,cities_en:$cities_en,last_seen_unix:$last_seen,first_seen_unix:$first_seen,display_until_unix:$display_until}')
            jq --argjson pa "$pre_obj" '.pre_alert = $pa' "$STATE_FILE"
            return
        elif [[ "$prev_cat" == "14" ]] && [[ "$cat" == "14" ]] && [[ "$prev_id" != "$id" ]]; then
            # New pre-alert replacing existing pre-alert with different ID → merge cities if TTL active
            local prev_du
            prev_du=$(jq -r '.display_until_unix // 0' "$STATE_FILE" 2>/dev/null)
            local now_merge
            now_merge=$(date +%s)
            if [[ "$prev_du" != "0" ]] && (( prev_du > now_merge )); then
                cities=$(jq -s '.[0] + .[1] | unique' <(echo "$cities") <(jq '.cities // []' "$STATE_FILE") 2>/dev/null)
                cities_en=$(jq -s '.[0] + .[1] | unique' <(echo "$cities_en") <(jq '.cities_en // []' "$STATE_FILE") 2>/dev/null)
                # Keep earlier first_seen
                if [[ "$prev_first" != "0" ]] && (( prev_first < first_seen )); then
                    first_seen="$prev_first"
                fi
                # Keep later display_until
                if (( prev_du > display_until )); then
                    display_until="$prev_du"
                fi
                log "PRE-ALERT MERGE (main): combined ${id} with existing ${prev_id}"
            fi
        elif [[ "$prev_cat" == "14" ]] && [[ "$cat" =~ ^(1|2|6)$ ]]; then
            # Missile/UAV overwriting pre-alert → preserve pre-alert
            pre_alert=$(jq -c '{alert_id,cat,title,cities,cities_en,last_seen_unix,first_seen_unix,display_until_unix}' "$STATE_FILE" 2>/dev/null)
        else
            # Carry forward pre_alert if its own TTL is still active, regardless of main cat
            local existing_pre
            existing_pre=$(jq -c '.pre_alert // null' "$STATE_FILE" 2>/dev/null)
            if [[ -n "$existing_pre" ]] && [[ "$existing_pre" != "null" ]]; then
                local existing_pre_du now_cf
                existing_pre_du=$(echo "$existing_pre" | jq -r '.display_until_unix // 0' 2>/dev/null)
                now_cf=$(date +%s)
                if [[ "$existing_pre_du" != "0" ]] && (( existing_pre_du >= now_cf )); then
                    pre_alert="$existing_pre"
                fi
            fi
        fi
    fi
    jq -n --arg id "$id" --arg cat "$cat" --arg title "$title" \
        --argjson cities "$cities" --argjson cities_en "$cities_en" \
        --argjson last_seen "$last_seen" --argjson cleared "$cleared" \
        --argjson first_seen "$first_seen" --argjson display_until "$display_until" \
        --argjson pre_alert "$pre_alert" \
        '{alert_id:$id,cat:$cat,title:$title,cities:$cities,cities_en:$cities_en,last_seen_unix:$last_seen,cleared_unix:$cleared,first_seen_unix:$first_seen,display_until_unix:$display_until,pre_alert:$pre_alert}'
}

# Play alert sound with per-class cooldown (non-blocking)
# Args: $1=sound_class ("missile" or "pre_alert"), $2=sound_file, $3=alert_id
play_sound() {
    local sound_class="$1"
    local sound_file="$2"
    local current_alert_id="$3"
    if [[ "$RED_ALERT_SOUND" == "off" ]]; then return; fi
    # Per-class cooldown: missiles 60s, pre-alerts 120s
    local cooldown
    case "$sound_class" in
        missile)   cooldown="${RED_ALERT_SOUND_COOLDOWN_MISSILE:-60}" ;;
        pre_alert) cooldown="${RED_ALERT_SOUND_COOLDOWN_PRE:-120}" ;;
        *)         cooldown="${RED_ALERT_SOUND_COOLDOWN:-60}" ;;
    esac
    local cooldown_file="${STATE_DIR}/red_alert_last_sound_${sound_class}"
    if [[ -f "$cooldown_file" ]]; then
        local last_time
        last_time=$(cat "$cooldown_file" 2>/dev/null)
        local now_secs
        now_secs=$(date +%s)
        if [[ -n "$last_time" ]] && (( now_secs - last_time < cooldown )); then return; fi
    fi
    if [[ ! -f "$sound_file" ]]; then
        log "Sound file not found: $sound_file"
        return
    fi
    date +%s > "$cooldown_file"
    # macOS: afplay, Linux: paplay or aplay
    if command -v afplay &>/dev/null; then
        afplay "$sound_file" &
    elif command -v paplay &>/dev/null; then
        paplay "$sound_file" &
    elif command -v aplay &>/dev/null; then
        aplay "$sound_file" &
    fi
    log "Sound played: $(basename "$sound_file") [$sound_class] for alert $current_alert_id"
}

# Translate Hebrew city names to English using districts file
# Input: JSON array of Hebrew city names, Output: JSON array of English names
translate_cities() {
    local cities_json="$1"
    if [[ ! -f "$DISTRICTS_FILE" ]]; then
        echo "$cities_json"
        return
    fi
    # For each Hebrew city, find the matching English label
    jq -c --slurpfile districts "$DISTRICTS_FILE" '
        [.[] | . as $city |
            ($districts[0] | map(select(.label_he == $city)) | .[0].label // null) as $exact |
            if $exact then $exact
            else
                ($districts[0] | map(select(.label_he != null and ($city | tostring | contains(.label_he)))) | .[0].label // null) as $partial |
                if $partial then $partial
                else $city
                end
            end
        ]
    ' <<< "$cities_json" 2>/dev/null || echo "$cities_json"
}

# Check if any alert cities match the user's filter (for sound decisions)
# SYNC: keep city mapping in sync with claude-pulse:filter_alert_cities()
# Returns 0 (true) if match found or mode=all, 1 (false) otherwise
cities_match_filter() {
    local cities_he="$1"
    local cities_en="$2"
    # Mode=all or no filter → always match
    if [[ "$RED_ALERT_MODE" == "all" ]] || [[ -z "$RED_ALERT_CITIES" ]]; then
        return 0
    fi
    IFS=',' read -ra filters <<< "$RED_ALERT_CITIES"
    for filter in "${filters[@]}"; do
        filter=$(echo "$filter" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
        [[ -z "$filter" ]] && continue
        # Map English filter to Hebrew (same map as statusline)
        hebrew=""
        case "$filter" in
            "tel aviv") hebrew="תל אביב" ;;
            "ramat gan") hebrew="רמת גן" ;;
            "jerusalem") hebrew="ירושלים" ;;
            "haifa") hebrew="חיפה" ;;
            "beer sheva"|"beersheba"|"beersheva") hebrew="באר שבע" ;;
            "ashdod") hebrew="אשדוד" ;;
            "ashkelon") hebrew="אשקלון" ;;
            "netanya") hebrew="נתניה" ;;
            "herzliya") hebrew="הרצליה" ;;
            "petah tikva") hebrew="פתח תקווה" ;;
            "rishon lezion") hebrew="ראשון לציון" ;;
            "holon") hebrew="חולון" ;;
            "bat yam") hebrew="בת ים" ;;
            "bnei brak") hebrew="בני ברק" ;;
            "rehovot") hebrew="רחובות" ;;
            "kfar saba") hebrew="כפר סבא" ;;
            "ra'anana"|"raanana") hebrew="רעננה" ;;
            "modiin") hebrew="מודיעין" ;;
            "eilat") hebrew="אילת" ;;
            "nazareth") hebrew="נצרת" ;;
            "acre"|"akko") hebrew="עכו" ;;
            "tiberias") hebrew="טבריה" ;;
            "sderot") hebrew="שדרות" ;;
            "kiryat shmona") hebrew="קריית שמונה" ;;
            "nahariya") hebrew="נהריה" ;;
            "lod") hebrew="לוד" ;;
            "ramla") hebrew="רמלה" ;;
            "givatayim") hebrew="גבעתיים" ;;
            "hod hasharon") hebrew="הוד השרון" ;;
        esac
        # Check against English city names
        while IFS= read -r city; do
            [[ -z "$city" ]] && continue
            city_lower=$(echo "$city" | tr '[:upper:]' '[:lower:]')
            if [[ "$city_lower" == *"$filter"* ]]; then
                return 0
            fi
        done <<< "$(echo "$cities_en" | jq -r '.[]?' 2>/dev/null)"
        # Check against Hebrew city names (mapped or direct)
        while IFS= read -r city; do
            [[ -z "$city" ]] && continue
            if [[ -n "$hebrew" ]] && [[ "$city" == *"$hebrew"* ]]; then
                return 0
            fi
            if [[ "$city" == *"$filter"* ]]; then
                return 0
            fi
        done <<< "$(echo "$cities_he" | jq -r '.[]?' 2>/dev/null)"
    done
    return 1
}

# Atomic singleton lock (mkdir is atomic — only one process wins)
# PID stored inside lock dir so ownership is coupled with the lock
LOCK_DIR="${STATE_DIR}/daemon.lock"
LOCK_PID="${LOCK_DIR}/pid"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # Lock exists — check if holder is still alive via pid inside lock
    if [[ -f "$LOCK_PID" ]]; then
        existing_pid=$(cat "$LOCK_PID" 2>/dev/null)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            [[ -n "$RED_ALERT_DEBUG" ]] && log "DEBUG: Lock held by live PID $existing_pid, exiting"
            exit 0
        fi
    fi
    # Stale lock (dead process or no pid yet) — wait briefly then check again
    [[ -n "$RED_ALERT_DEBUG" ]] && log "DEBUG: Lock exists but no live PID, waiting 1s..."
    sleep 1
    if [[ -f "$LOCK_PID" ]]; then
        existing_pid=$(cat "$LOCK_PID" 2>/dev/null)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            [[ -n "$RED_ALERT_DEBUG" ]] && log "DEBUG: PID $existing_pid appeared after wait, exiting"
            exit 0
        fi
    fi
    # Truly stale — reclaim
    [[ -n "$RED_ALERT_DEBUG" ]] && log "DEBUG: Reclaiming stale lock (PID was: $(cat "$LOCK_PID" 2>/dev/null || echo 'none'))"
    rm -rf "$LOCK_DIR"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        [[ -n "$RED_ALERT_DEBUG" ]] && log "DEBUG: Failed to reclaim lock, another process won, exiting"
        exit 0
    fi
fi

# We hold the lock — write PID immediately (inside lock dir + state dir)
echo $$ > "$LOCK_PID"
echo $$ > "$PID_FILE"
[[ -n "$DAEMON_VERSION" ]] && echo "$DAEMON_VERSION" > "$VERSION_FILE"
log "Daemon started (PID $$, v${DAEMON_VERSION:-unknown}, mode=${RED_ALERT_MODE:-normal})"

mock_index=0

HEARTBEAT_FILE="${STATE_DIR}/heartbeat"
HEARTBEAT_TIMEOUT="${RED_ALERT_HEARTBEAT_TIMEOUT:-300}"
DAEMON_START_TIME=$(date +%s)
PGREP_MISS_COUNT=0
PGREP_MISS_THRESHOLD=3

# API failure tracking — exponential backoff, daemon never dies
# Tiers: 1-10 = 2s, 11+ = 10s (capped so main loop liveness checks run)
# First valid JSON response resets to normal 2s polling
API_FAIL_COUNT=0

# Touch heartbeat on startup to prevent immediate exit from stale file
touch "$HEARTBEAT_FILE" 2>/dev/null

while true; do
    now=$(date +%s)
    daemon_uptime=$(( now - DAEMON_START_TIME ))

    # Check if Claude Code is still running
    _claude_alive=false
    if (( daemon_uptime > 30 )) && command -v pgrep >/dev/null 2>&1; then
        if pgrep -x "claude" >/dev/null 2>&1; then
            PGREP_MISS_COUNT=0
            _claude_alive=true
        else
            PGREP_MISS_COUNT=$(( PGREP_MISS_COUNT + 1 ))
            if (( PGREP_MISS_COUNT >= PGREP_MISS_THRESHOLD )); then
                log "No Claude Code process for ${PGREP_MISS_COUNT} checks, exiting"
                exit 0
            fi
        fi
    fi

    # Heartbeat fallback — only check if pgrep didn't confirm claude is alive
    if [[ "$_claude_alive" == "false" ]] && (( daemon_uptime > HEARTBEAT_TIMEOUT )); then
        if [[ -f "$HEARTBEAT_FILE" ]]; then
            heartbeat_age=$(( now - $(stat -f%m "$HEARTBEAT_FILE" 2>/dev/null || stat -c%Y "$HEARTBEAT_FILE" 2>/dev/null || echo "$now") ))
            if (( heartbeat_age > HEARTBEAT_TIMEOUT )); then
                log "No statusline heartbeat for ${heartbeat_age}s, exiting"
                exit 0
            fi
        fi
    fi

    if [[ "$RED_ALERT_MODE" == "mock" ]]; then
        # Mock mode: cycle through scenarios, no network calls
        # Exit after one full cycle in mock mode
        if (( mock_index >= ${#MOCK_SCENARIOS[@]} )); then
            log "Mock cycle complete, exiting"
            exit 0
        fi
        mock_data="${MOCK_SCENARIOS[$mock_index]}"
        mock_index=$(( mock_index + 1 ))

        if [[ "$mock_data" == "{}" ]] || [[ -z "$mock_data" ]]; then
            # Quiet period — write empty state
            write_state "$(build_state "" "" "" "[]" "[]" 0 "$now")"
        else
            alert_id="mock_$(date +%s%N)"
            cat_val=$(echo "$mock_data" | jq -r '.cat // ""')
            title=$(echo "$mock_data" | jq -r '.title // ""')
            cities=$(echo "$mock_data" | jq -c '.data // []')
            cities_en=$(translate_cities "$cities")
            write_state "$(build_state "$alert_id" "$cat_val" "$title" "$cities" "$cities_en" "$now" 0)"
            # Play sound only if cities match user's filter
            if cities_match_filter "$cities" "$cities_en"; then
                case "$cat_val" in
                    14) play_sound "pre_alert" "$SOUND_DIR/early.m4a" "$alert_id" ;;
                    1|2|6) play_sound "missile" "$SOUND_DIR/go.m4a" "$alert_id" ;;
                esac
            fi
        fi

        sleep "${RED_ALERT_MOCK_INTERVAL:-10}"
        continue
    fi

    # Normal/all mode: poll the API
    response=$(curl -s --max-time 5 \
        -H "Referer: https://www.oref.org.il/" \
        -H "User-Agent: Mozilla/5.0" \
        -H "Cache-Control: no-cache" \
        "$API_URL" 2>/dev/null)

    # Strip UTF-8 BOM and null bytes
    response=$(echo "$response" | sed 's/^\xEF\xBB\xBF//' | tr -d '\0')

    # Track consecutive failures — only empty response or invalid JSON counts as failure
    # Valid JSON (even without .cat) means the API is reachable — reset counter
    _is_failure=false
    if [[ -z "$response" ]] || ! echo "$response" | jq empty 2>/dev/null; then
        _is_failure=true
    else
        # Valid JSON response — API is reachable, reset backoff
        API_FAIL_COUNT=0
    fi

    if [[ "$_is_failure" == "true" ]]; then
        ((API_FAIL_COUNT++))
        # Exponential backoff — daemon stays alive, self-heals on network recovery
        # Sleep here then continue to top of main loop where liveness checks run
        if (( API_FAIL_COUNT <= 10 )); then
            sleep "$POLL_INTERVAL"
        elif (( API_FAIL_COUNT <= 20 )); then
            sleep 10
        elif (( API_FAIL_COUNT <= 30 )); then
            sleep 10  # cap at 10s per iteration; 30 iterations ≈ 5 min total
        else
            if (( API_FAIL_COUNT == 31 )); then
                log "API unreachable, entering slow backoff (will resume on network recovery)"
            fi
            sleep 10  # stay at 10s — main loop liveness checks run every iteration
        fi
        continue
    fi

    # Check if response has alert data
    cat_val=$(echo "$response" | jq -r '.cat // ""' 2>/dev/null)

    if [[ -z "$cat_val" ]] || [[ "$cat_val" == "null" ]]; then
        # No active alert — preserve last state but don't update last_seen_unix
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Extract alert fields
    alert_id=$(echo "$response" | jq -r '.id // ""' 2>/dev/null)
    title=$(echo "$response" | jq -r '.title // ""' 2>/dev/null)
    cities=$(echo "$response" | jq -c '[.data[]? | select(. != null and . != "") | gsub("^\\s+|\\s+$"; "")]' 2>/dev/null)
    [[ -z "$cities" ]] && cities="[]"

    # Handle alert categories
    case "$cat_val" in
        13)
            # All clear
            log "All clear received (id: $alert_id)"
            cities_en=$(translate_cities "$cities")
            write_state "$(build_state "$alert_id" "13" "$title" "$cities" "$cities_en" "$now" "$now")"
            ;;
        14)
            # cat=14 is a junk drawer: forward-looking pre-alerts AND backward-looking
            # resolutions (e.g., "הוסר החשש", "נשלל החשש"). Resolutions must NOT render
            # as "be prepared" — match cat=10 "הסתיים" behavior: log only, no state write,
            # let any prior state expire naturally.
            if is_resolution_title "$title"; then
                log "RESOLUTION cat=14 routed=skip title=$title id=$alert_id cities=$cities"
            else
                log "Pre-alert received (id: $alert_id)"
                cities_en=$(translate_cities "$cities")
                write_state "$(build_state "$alert_id" "14" "$title" "$cities" "$cities_en" "$now" 0)"
                if cities_match_filter "$cities" "$cities_en"; then
                    play_sound "pre_alert" "$SOUND_DIR/early.m4a" "$alert_id"
                fi
            fi
            ;;
        10)
            # Cat 10 has multiple meanings based on title
            if is_resolution_title "$title"; then
                # Event ended/removed/cancelled — log only, let display_until expire naturally
                # The red banner stops on its own via display_until_unix,
                # then "Recent" tier shows for up to 5 min from first_seen
                log "EVENT ENDED cat=$cat_val title=$title id=$alert_id cities=$cities"
            else
                # Pre-alert or other warning (e.g., "בדקות הקרובות צפויות להתקבל התרעות")
                log "PRE-ALERT cat=$cat_val title=$title id=$alert_id cities=$cities"
                cities_en=$(translate_cities "$cities")
                write_state "$(build_state "$alert_id" "14" "$title" "$cities" "$cities_en" "$now" 0)"
                if cities_match_filter "$cities" "$cities_en"; then
                    play_sound "pre_alert" "$SOUND_DIR/early.m4a" "$alert_id"
                fi
            fi
            ;;
        1|2|3|4|5|6|7|8|9|11|12|101|102|103|104|105|106|107)
            # Active alert or drill
            log "ALERT cat=$cat_val title=$title id=$alert_id cities=$cities"
            cities_en=$(translate_cities "$cities")
            write_state "$(build_state "$alert_id" "$cat_val" "$title" "$cities" "$cities_en" "$now" 0)"
            if cities_match_filter "$cities" "$cities_en"; then
                case "$cat_val" in
                    1|2|6) play_sound "missile" "$SOUND_DIR/go.m4a" "$alert_id" ;;
                esac
            fi
            ;;
        *)
            log "Unknown category: $cat_val"
            ;;
    esac

    sleep "$POLL_INTERVAL"
done
