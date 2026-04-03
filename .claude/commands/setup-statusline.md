---
name: setup-statusline
description: Interactive setup for claude-pulse — install, choose density, configure Red Alert
user_invocable: true
---

# Setup claude-pulse

Complete onboarding. Claude runs each step, using `AskUserQuestion` for choices.

## 1. Install files

First, check if claude-pulse is already installed:

```bash
[[ -f "$HOME/.claude/statusline-command.sh" ]] && echo "INSTALLED" || echo "NOT_INSTALLED"
```

**If NOT_INSTALLED**: the repo files are needed. Verify we're in the claude-pulse repo directory (check `claude-pulse` file exists in cwd). If not, tell the user: "First-time install requires the repo. Run: `git clone https://github.com/omriariav/claude-pulse && cd claude-pulse && /setup-statusline`" and stop.

**If NOT_INSTALLED** (in repo): copy files from the repo:

```bash
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR/static" "$CLAUDE_DIR/commands"
cp claude-pulse "$CLAUDE_DIR/statusline-command.sh" && chmod +x "$CLAUDE_DIR/statusline-command.sh"
cp red-alert-daemon.sh "$CLAUDE_DIR/red-alert-daemon.sh" && chmod +x "$CLAUDE_DIR/red-alert-daemon.sh"
cp update.sh "$CLAUDE_DIR/update.sh" && chmod +x "$CLAUDE_DIR/update.sh"
cp static/*.m4a "$CLAUDE_DIR/static/" 2>/dev/null || true
curl -s --max-time 10 -o "$CLAUDE_DIR/districts_eng.json" "https://www.oref.org.il/districts/districts_eng.json" || true
for skill in setup-statusline update-pulse uninstall-statusline uninstall-red-alert; do
    cp ".claude/commands/${skill}.md" "$CLAUDE_DIR/commands/${skill}.md"
done
```

**If INSTALLED**: skip file copying — scripts are already in place and OTA keeps them updated. Proceed to step 2.

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
echo "${G}🧠 [██████░░░░░░░░░░░░░░] 31%${R} · 🤖 Sonnet 4.6 (1M) · 💬 2503-work · 🌿 fix/alert-city-accumulation (#25) · 📁 claude-pulse"
echo "⚡ ${G}5h: 5%${R} · 7d:  2% · 💰  \$12 · 🟢 Alerts daemon ON ${DM}(1)${R}"
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

Read then Edit `~/.claude/settings.json` `env` object.

**First: remove stale Red Alert env vars** to avoid conflicts from previous config:
Remove `RED_ALERT_CITIES`, `RED_ALERT_MODE`, `RED_ALERT_SOUND` from `env` if present.

**Then set fresh values based on choice:**

| Choice | Env vars to set |
|--------|----------------|
| Specific + sound | `"RED_ALERT_CITIES": "<cities>"` |
| Specific, no sound | `"RED_ALERT_CITIES": "<cities>", "RED_ALERT_SOUND": "off"` |
| All + sound | `"RED_ALERT_MODE": "all"` |
| All, no sound | `"RED_ALERT_MODE": "all", "RED_ALERT_SOUND": "off"` |

Do NOT remove other env vars (e.g., `CLAUDE_PULSE_DENSITY`).

## 7. Daemon (macOS, if Red Alert enabled)

```bash
launchctl unload ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist 2>/dev/null || true
pkill -9 -f red-alert-daemon 2>/dev/null || true
rm -f ~/.local/state/claude-pulse/red_alert_daemon.pid ~/.local/state/claude-pulse/red_alert_last_sound ~/.local/state/claude-pulse/red_alert_state.json
```

If the plist `~/Library/LaunchAgents/com.claude-pulse.red-alert.plist` does not exist, create it using the Write tool. **IMPORTANT**: All paths in the plist must be absolute (use the user's actual `$HOME`, e.g. `/Users/username/...`). `launchd` does NOT expand `~`. Use the standard structure: Label=com.claude-pulse.red-alert, ProgramArguments=$HOME/.claude/red-alert-daemon.sh, RunAtLoad=false, KeepAlive=false, WorkingDirectory=$HOME, stdout/stderr to $HOME/.local/state/claude-pulse/, EnvironmentVariables with HOME and PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin. Then Edit the plist — add env vars to `EnvironmentVariables`, set `RunAtLoad` to `<true/>`, and ensure `KeepAlive` is `<false/>` (the daemon self-heals via exponential backoff; KeepAlive causes restart loops).

```bash
launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist
launchctl kickstart "gui/$(id -u)/com.claude-pulse.red-alert" >/dev/null 2>&1 || true
```

Add SessionStart hooks — Read then Edit `~/.claude/settings.json`, merge into `hooks.SessionStart` array (don't clobber existing hooks). Each entry MUST use the nested `hooks` array format required by the schema:

```json
{"hooks":{"SessionStart":[
  {"hooks":[{"type":"command","command":"~/.claude/update.sh >/dev/null 2>&1 &","timeout":5}]},
  {"hooks":[{"type":"command","command":"if [ -f ~/.local/state/claude-pulse/daemon_restart_requested ]; then rm -f ~/.local/state/claude-pulse/daemon_restart_requested; launchctl kickstart -k gui/$(id -u)/com.claude-pulse.red-alert 2>/dev/null; fi","timeout":5}]},
  {"hooks":[{"type":"command","command":"launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist 2>/dev/null; true","timeout":5}]}
]}}
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
