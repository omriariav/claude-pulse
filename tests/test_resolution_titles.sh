#!/bin/bash
# Tests for is_resolution_title() — Pikud HaOref "threat removed/cancelled" detection.
# Resolution titles arrive under cat=14 (or cat=10) and must NOT render as "be prepared".

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/helpers.sh"
setup

DAEMON="$TESTS_DIR/../red-alert-daemon.sh"

# Pull the function out of the daemon source without running its main loop
eval "$(sed -n '/^is_resolution_title()/,/^}/p' "$DAEMON")"

echo "Testing is_resolution_title()..."

# Resolutions — must match (return 0)
resolution_titles=(
    "הוסר החשש לחדירת מחבלים"           # "concern of terrorist infiltration removed" (the original bug)
    "הוסרה ההתרעה"                       # feminine "removed"
    "הוסרו ההתרעות"                      # plural "removed"
    "הסתיים האירוע"                      # "event ended" (cat=10 precedent)
    "הסתיימה ההתקפה"                     # feminine "ended"
    "הסתיימו ההתרעות"                    # plural "ended"
    "בוטל האירוע"                        # "event cancelled"
    "בוטלה ההתרעה"                       # feminine "cancelled"
    "בוטלו ההתרעות"                      # plural "cancelled"
    "נשלל החשש לחדירת מחבלים"          # "infiltration concern ruled out"
    "נשללה החדירה"                       # feminine "ruled out"
    "נשללו ההתרעות"                      # plural "ruled out"
    "אין חשש לחדירת מחבלים"             # "no concern of infiltration"
)

for title in "${resolution_titles[@]}"; do
    if is_resolution_title "$title"; then
        echo -e "  ${GREEN}PASS${RESET} matches resolution: $title"
        ((PASS_COUNT++))
    else
        echo -e "  ${RED}FAIL${RESET} should match resolution: $title"
        ((FAIL_COUNT++))
    fi
done

# Legitimate pre-alerts — must NOT match (return 1)
pre_alert_titles=(
    "בדקות הקרובות צפויות להתקבל התרעות"  # "in the coming minutes expect alerts"
    "ירי רקטות וטילים"                      # "rocket and missile fire"
    "חדירת כלי טיס עוין"                    # "hostile aircraft infiltration"
    "חשד לחדירת מחבלים"                    # "suspected terrorist infiltration"
    "התרעה מוקדמת"                          # "early warning"
    ""                                       # empty title
)

for title in "${pre_alert_titles[@]}"; do
    if ! is_resolution_title "$title"; then
        echo -e "  ${GREEN}PASS${RESET} not a resolution: ${title:-<empty>}"
        ((PASS_COUNT++))
    else
        echo -e "  ${RED}FAIL${RESET} should NOT match resolution: $title"
        ((FAIL_COUNT++))
    fi
done

cleanup
report
