#!/bin/bash
# Tests for daemon per-sound-class cooldown logic

source "$(dirname "$0")/helpers.sh"
setup

echo "Testing daemon sound cooldown..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$TEST_TMPDIR"

# Source just the play_sound function from the daemon for isolated testing
# We can't source the whole daemon (it would start running), so we extract what we need
export RED_ALERT_SOUND=""  # not "off"
export STATE_DIR="$TEST_TMPDIR"
SOUND_DIR="$SCRIPT_DIR/static"

# Create a mock sound file (we won't actually play it)
mkdir -p "$TEST_TMPDIR/static"
touch "$TEST_TMPDIR/static/go.m4a"
touch "$TEST_TMPDIR/static/early.m4a"
SOUND_DIR="$TEST_TMPDIR/static"

# Extract play_sound and log functions from daemon
eval "$(sed -n '/^log()/,/^}/p' "$SCRIPT_DIR/red-alert-daemon.sh" | sed "s|\$LOG_FILE|$TEST_TMPDIR/test.log|")"
eval "$(sed -n '/^play_sound()/,/^}/p' "$SCRIPT_DIR/red-alert-daemon.sh")"

# Override sound commands to just log (don't actually play)
afplay() { echo "WOULD_PLAY: $1" >> "$TEST_TMPDIR/sound_plays.log"; }
export -f afplay

# test_missile_cooldown: second missile within 40s is suppressed
play_sound "missile" "$SOUND_DIR/go.m4a" "alert_1"
play_sound "missile" "$SOUND_DIR/go.m4a" "alert_2"
missile_plays=$(grep -c "WOULD_PLAY.*go.m4a" "$TEST_TMPDIR/sound_plays.log" 2>/dev/null || echo "0")
assert_equals "$missile_plays" "1" "missile cooldown: second play within cooldown suppressed"

# test_pre_alert_cooldown: second pre-alert within 120s is suppressed
play_sound "pre_alert" "$SOUND_DIR/early.m4a" "alert_3"
play_sound "pre_alert" "$SOUND_DIR/early.m4a" "alert_4"
pre_plays=$(grep -c "WOULD_PLAY.*early.m4a" "$TEST_TMPDIR/sound_plays.log" 2>/dev/null || echo "0")
assert_equals "$pre_plays" "1" "pre-alert cooldown: second play within cooldown suppressed"

# test_cross_class: missile then pre-alert both play (different cooldown files)
rm -f "$TEST_TMPDIR/sound_plays.log"
rm -f "$TEST_TMPDIR/red_alert_last_sound_missile" "$TEST_TMPDIR/red_alert_last_sound_pre_alert"
play_sound "missile" "$SOUND_DIR/go.m4a" "alert_5"
play_sound "pre_alert" "$SOUND_DIR/early.m4a" "alert_6"
total_plays=$(wc -l < "$TEST_TMPDIR/sound_plays.log" 2>/dev/null | tr -d ' ')
assert_equals "$total_plays" "2" "cross-class: missile and pre-alert both play (independent cooldowns)"

# test_separate_cooldown_files: each class has its own file
assert_contains "$(ls "$TEST_TMPDIR")" "red_alert_last_sound_missile" "separate files: missile cooldown file exists"
assert_contains "$(ls "$TEST_TMPDIR")" "red_alert_last_sound_pre_alert" "separate files: pre-alert cooldown file exists"

cleanup
report
