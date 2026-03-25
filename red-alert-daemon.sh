#!/bin/bash
# red-alert-daemon.sh: Background daemon for Pikud HaOref alert monitoring
# Polls the official alert API every 2 seconds and writes state to disk
# Supports: normal mode (API), all mode (API, no filter), mock mode (offline testing)

STATE_DIR="${RED_ALERT_STATE_DIR:-$HOME/.local/state/claude-pulse}"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE_FILE="${STATE_DIR}/red_alert_state.json"
PID_FILE="${STATE_DIR}/red_alert_daemon.pid"
LOG_FILE="${STATE_DIR}/red_alert_daemon.log"
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
SOUND_PLAYED_FILE="${STATE_DIR}/red_alert_last_sound"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

cleanup() {
    log "Daemon stopping (PID $$)"
    # Only remove PID file and lock if they're ours
    current_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [[ "$current_pid" == "$$" ]]; then
        rm -f "$PID_FILE"
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

# Build state JSON safely using jq (handles quotes/escapes in API data)
build_state() {
    local id="$1" cat="$2" title="$3" cities="$4" cities_en="$5" last_seen="$6" cleared="$7"
    jq -n --arg id "$id" --arg cat "$cat" --arg title "$title" \
        --argjson cities "$cities" --argjson cities_en "$cities_en" \
        --argjson last_seen "$last_seen" --argjson cleared "$cleared" \
        '{alert_id:$id,cat:$cat,title:$title,cities:$cities,cities_en:$cities_en,last_seen_unix:$last_seen,cleared_unix:$cleared}'
}

# Play alert sound (only once per alert_id, non-blocking)
play_sound() {
    local sound_file="$1"
    local current_alert_id="$2"
    # Skip if sound disabled or played recently (cooldown configurable via RED_ALERT_SOUND_COOLDOWN)
    if [[ "$RED_ALERT_SOUND" == "off" ]]; then return; fi
    local cooldown="${RED_ALERT_SOUND_COOLDOWN:-20}"
    if [[ -f "$SOUND_PLAYED_FILE" ]]; then
        local last_time
        last_time=$(cat "$SOUND_PLAYED_FILE" 2>/dev/null)
        local now_secs
        now_secs=$(date +%s)
        if [[ -n "$last_time" ]] && (( now_secs - last_time < cooldown )); then return; fi
    fi
    if [[ ! -f "$sound_file" ]]; then
        log "Sound file not found: $sound_file"
        return
    fi
    date +%s > "$SOUND_PLAYED_FILE"
    # macOS: afplay, Linux: paplay or aplay
    if command -v afplay &>/dev/null; then
        afplay "$sound_file" &
    elif command -v paplay &>/dev/null; then
        paplay "$sound_file" &
    elif command -v aplay &>/dev/null; then
        aplay "$sound_file" &
    fi
    log "Sound played: $(basename "$sound_file") for alert $current_alert_id"
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
log "Daemon started (PID $$, mode=${RED_ALERT_MODE:-normal})"

mock_index=0

HEARTBEAT_FILE="${STATE_DIR}/heartbeat"
HEARTBEAT_TIMEOUT="${RED_ALERT_HEARTBEAT_TIMEOUT:-120}"
DAEMON_START_TIME=$(date +%s)

# Touch heartbeat on startup to prevent immediate exit from stale file
touch "$HEARTBEAT_FILE" 2>/dev/null

while true; do
    now=$(date +%s)

    # Exit if no statusline has refreshed recently (all Claude Code instances closed)
    # Skip check during first HEARTBEAT_TIMEOUT seconds (give statusline time to start)
    daemon_uptime=$(( now - DAEMON_START_TIME ))
    if (( daemon_uptime > HEARTBEAT_TIMEOUT )); then
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
                    14) play_sound "$SOUND_DIR/early.m4a" "$alert_id" ;;
                    1|2) play_sound "$SOUND_DIR/go.m4a" "$alert_id" ;;
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

    # Skip if empty or invalid JSON
    if [[ -z "$response" ]] || ! echo "$response" | jq empty 2>/dev/null; then
        sleep "$POLL_INTERVAL"
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
            # Pre-alert
            log "Pre-alert received (id: $alert_id)"
            cities_en=$(translate_cities "$cities")
            write_state "$(build_state "$alert_id" "14" "$title" "$cities" "$cities_en" "$now" 0)"
            if cities_match_filter "$cities" "$cities_en"; then
                play_sound "$SOUND_DIR/early.m4a" "$alert_id"
            fi
            ;;
        1|2|3|4|5|6|7|8|9|10|11|12|101|102|103|104|105|106|107)
            # Active alert or drill
            log "ALERT cat=$cat_val title=$title id=$alert_id cities=$cities"
            cities_en=$(translate_cities "$cities")
            write_state "$(build_state "$alert_id" "$cat_val" "$title" "$cities" "$cities_en" "$now" 0)"
            if cities_match_filter "$cities" "$cities_en"; then
                case "$cat_val" in
                    1|2) play_sound "$SOUND_DIR/go.m4a" "$alert_id" ;;
                esac
            fi
            ;;
        *)
            log "Unknown category: $cat_val"
            ;;
    esac

    sleep "$POLL_INTERVAL"
done
