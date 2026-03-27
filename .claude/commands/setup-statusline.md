---
name: setup-statusline
description: Interactive setup for claude-pulse — install, choose density, configure Red Alert
user_invocable: true
---

# Setup claude-pulse

Complete onboarding. Claude runs each step, using `AskUserQuestion` for choices.

## 1. Install files

```bash
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR/static"
cp claude-pulse "$CLAUDE_DIR/statusline-command.sh" && chmod +x "$CLAUDE_DIR/statusline-command.sh"
cp red-alert-daemon.sh "$CLAUDE_DIR/red-alert-daemon.sh" && chmod +x "$CLAUDE_DIR/red-alert-daemon.sh"
cp static/*.m4a "$CLAUDE_DIR/static/" 2>/dev/null || true
curl -s --max-time 10 -o "$CLAUDE_DIR/districts_eng.json" "https://www.oref.org.il/districts/districts_eng.json" || true
```

## 2. Configure statusline

Read `~/.claude/settings.json`, then Edit to add/update:

```json
"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh"}
```

Merge — do NOT overwrite other keys.

## 3. Density selection

Run this bash to render preview (non-interactive output only):

```bash
bash << 'PREVIEW'
R=$'\033[0m'; G=$'\033[38;2;80;250;123m'; DM=$'\033[38;2;128;128;128m'; B=$'\033[1m'; S="${DM}|${R}"
echo ""
echo "${B}Choose your statusline density:${R}"
echo ""
echo "${B}1) Minimal${R} ${DM}— single line, narrow terminals (<100 cols)${R}"
echo "${G}🧠 31% Son4.6(1M)${R} ${S} 2503-work ${S} #25 pulse ${S} ⚡5h: 5% 7d: 2% ${S} 🟢${DM}(1)${R}"
echo ""
echo "${B}2) Regular${R} ${DM}— balanced two-line layout (100-159 cols)${R}"
echo "${G}🧠 ████░░░░░░ 31%${R}  🤖 Sonnet 4.6 (1M)  💬 2503-work  🌿 …accumulation (#25)  📁 claude-pulse"
echo "⚡ ${G}5h: 5%${R}  7d: 2%  🟢 Alerts ON ${DM}(1)${R}"
echo ""
echo "${B}3) Heavy${R} ${DM}— full detail, wide terminals (160+ cols)${R}"
echo "${G}🧠 [██████░░░░░░░░░░░░░░] 31%${R} · 🤖 Sonnet 4.6 (1M) · 💬 2503-work · 🌿 fix/alert-city-accumulation (#25) · 📁 ~/Code/claude-pulse"
echo "⚡ ${G}5h: 5%${R} · 7d: 2% · 💰 \$0.42 · 🟢 Alerts daemon ON ${DM}(1)${R}"
echo ""
echo "${B}4) Auto${R} ${DM}— adapts to terminal width automatically [recommended]${R}"
echo ""
PREVIEW
```

`AskUserQuestion`: "Which density?"
- Options: "Auto (recommended)", "Minimal", "Regular", "Heavy"

Apply: Read then Edit `~/.claude/settings.json` `env` object:
- **Auto:** Remove `CLAUDE_PULSE_DENSITY` if present
- **Others:** `"CLAUDE_PULSE_DENSITY": "<choice>"`

Create `env` object if it doesn't exist.

## 4. Session cost display (heavy mode only)

Only ask this if user picked **Heavy** density (or Auto). Skip for Minimal/Regular.

`AskUserQuestion`: "Show session cost (💰) in the statusline? Most useful for API/pay-per-use plans."
- Options: "Yes - show cost", "No - I'm on Max/Pro (recommended)"

Apply: Read then Edit `~/.claude/settings.json` `env` object:
- **Yes:** Remove `CLAUDE_PULSE_HIDE_COST` if present
- **No:** Set `"CLAUDE_PULSE_HIDE_COST": "1"`

## 5. Red Alert

`AskUserQuestion`: "Enable Red Alert (Pikud HaOref) rocket alert notifications?"
- Options: "Yes - specific cities", "Yes - all alerts", "No - skip"

**"No - skip"** → jump to Step 8.
**"Yes - all alerts"** → skip to 5c.

### 5a. Cities

`AskUserQuestion`: "Which cities?"
- Options: "Tel Aviv", "Jerusalem", "Haifa", "Beer Sheva"
- multiSelect: true, user can type custom via "Other" (comma-separated)

### 5b. Zones

For each city, check sub-zones:
```bash
jq -r '[.[] | select(.label | startswith("<CITY> - ")) | .label] | .[]' "$HOME/.claude/districts_eng.json"
```
If zones exist, show numbered list in text, then `AskUserQuestion`:
"<CITY> has N zones (above). Monitor all or specific?"
- Options: "All of <CITY> (recommended)", "Specific zones — I'll type them"

Tell user: fuzzy matching works ("center" matches "Tel Aviv - City Center").

### 5c. Sound

`AskUserQuestion`: "Alert sound?"
- Options: "Yes (recommended)", "No - visual only"

## 6. Apply Red Alert env vars

Read then Edit `~/.claude/settings.json` `env` object — merge, don't overwrite:

| Choice | Env vars |
|--------|----------|
| Specific + sound | `"RED_ALERT_CITIES": "<cities>"` |
| Specific, no sound | `"RED_ALERT_CITIES": "<cities>", "RED_ALERT_SOUND": "off"` |
| All + sound | `"RED_ALERT_MODE": "all"` |
| All, no sound | `"RED_ALERT_MODE": "all", "RED_ALERT_SOUND": "off"` |

## 7. Daemon (macOS, if Red Alert enabled)

```bash
launchctl unload ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist 2>/dev/null || true
pkill -9 -f red-alert-daemon 2>/dev/null || true
rm -f ~/.local/state/claude-pulse/red_alert_daemon.pid ~/.local/state/claude-pulse/red_alert_last_sound ~/.local/state/claude-pulse/red_alert_state.json
```

Edit plist `~/Library/LaunchAgents/com.claude-pulse.red-alert.plist` — add env vars to `EnvironmentVariables`, set `KeepAlive` and `RunAtLoad` to `<true/>`.

```bash
launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist
launchctl kickstart "gui/$(id -u)/com.claude-pulse.red-alert" >/dev/null 2>&1 || true
```

Add SessionStart hook — Read then Edit `~/.claude/settings.json`, merge into `hooks`:

```json
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist; launchctl kickstart \"gui/$(id -u)/com.claude-pulse.red-alert\" >/dev/null 2>&1; true","timeout":5}]}]}}
```

## 8. Summary

```
claude-pulse setup complete!

Statusline:  ~/.claude/statusline-command.sh
Density:     <auto | minimal | regular | heavy>
Red Alert:   <cities | all | disabled>
Sound:       <on | off | n/a>

Reconfigure:        /setup-statusline
Remove everything:  /uninstall-statusline
Remove alerts only: /uninstall-red-alert
```
