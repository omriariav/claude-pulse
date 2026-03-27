---
name: setup-red-alert
description: Interactive setup for Red Alert (Pikud HaOref) notifications in claude-pulse statusline
user_invocable: true
---

# Setup Red Alert

Install claude-pulse with Red Alert (Pikud HaOref) rocket alert notifications.

## Steps

### 1. Copy files

Run these commands to install the scripts:

```bash
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR/static"
cp claude-pulse "$CLAUDE_DIR/statusline-command.sh" && chmod +x "$CLAUDE_DIR/statusline-command.sh"
cp red-alert-daemon.sh "$CLAUDE_DIR/red-alert-daemon.sh" && chmod +x "$CLAUDE_DIR/red-alert-daemon.sh"
cp static/*.m4a "$CLAUDE_DIR/static/" 2>/dev/null || true
```

### 2. Download district translations

```bash
curl -s --max-time 10 -o "$HOME/.claude/districts_eng.json" "https://www.oref.org.il/districts/districts_eng.json"
```

### 3. Configure statusline

Use the `update-config` skill or Edit tool to ensure `~/.claude/settings.json` has:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

### 4. Ask the user for Red Alert preferences

Use `AskUserQuestion` with these questions:

**Question 1:** "Would you like to enable Red Alert (Pikud HaOref) rocket alert notifications?"
- Options: "Yes - specific cities", "Yes - all alerts", "No - skip"

If "No - skip", stop here.

**If "Yes - all alerts":** skip to Question 4 (sound).

**If "Yes - specific cities":**

**Question 2:** "Which cities do you want to monitor?"
- Options: "Tel Aviv", "Jerusalem", "Haifa", "Beer Sheva"
- User can type custom cities via "Other" (comma-separated)
- multiSelect: true (allow picking multiple)

**Question 3 — Zone selection:** For EACH city the user picked, check if it has sub-zones by running:

```bash
jq -r '[.[] | select(.label | startswith("<CITY> - ")) | .label] | .[]' "$HOME/.claude/districts_eng.json"
```

If the city has zones (results are not empty), show the user the full list of zones as a numbered list in your text output, then ask with `AskUserQuestion`:

"<CITY> has N alert zones: [list them numbered in text above]. Monitor all zones or specific ones?"
- Options: "All of <CITY>" (recommended), "Specific zones — I'll type them"
- If user picks "Specific zones", they type zone names via "Other" (comma-separated, matching the numbered list you showed)

This avoids the 4-option limit in AskUserQuestion since the zone list is shown as text.

The filter uses fuzzy substring matching, so the user can type partial names:
- "center" → matches "Tel Aviv - City Center"
- "south" → matches "Tel Aviv - South and Jaffa"
- "yarkon" → matches "Tel Aviv - Across the Yarkon"
- "tel aviv" → matches ALL Tel Aviv zones

Tell the user they can use partial names. No need to type exact strings.

If the city has no zones, just use the city name as-is.

Build the final comma-separated city list from all answers. Use zone-specific names when the user picked individual zones (e.g., `Tel Aviv - City Center`), or the broad city name when they picked "All of <CITY>" (e.g., `Tel Aviv`).

**Question 4:** "Enable alert sound?"
- Options: "Yes (recommended)", "No - visual only"

### 5. Apply settings based on answers

Based on the user's choices, add the appropriate env vars to `~/.claude/settings.json` using Edit.

**Specific cities with sound:**
```json
{"env": {"RED_ALERT_CITIES": "<final city list>"}}
```

**Specific cities without sound:**
```json
{"env": {"RED_ALERT_CITIES": "<final city list>", "RED_ALERT_SOUND": "off"}}
```

**All alerts with sound:**
```json
{"env": {"RED_ALERT_MODE": "all"}}
```

**All alerts without sound:**
```json
{"env": {"RED_ALERT_MODE": "all", "RED_ALERT_SOUND": "off"}}
```

Merge into the existing `env` object in settings.json — do NOT overwrite other env vars.

### 6. Start the daemon via launchd (macOS)

After writing settings, start the daemon:

```bash
# Stop any existing daemon
launchctl unload ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist 2>/dev/null || true
pkill -9 -f red-alert-daemon 2>/dev/null || true
rm -f ~/.local/state/claude-pulse/red_alert_daemon.pid ~/.local/state/claude-pulse/red_alert_last_sound ~/.local/state/claude-pulse/red_alert_state.json

# Update plist with env vars so daemon gets the user's config
# The plist EnvironmentVariables dict needs RED_ALERT_CITIES/MODE/SOUND
```

Use the Edit tool to add the user's env vars to the plist at `~/Library/LaunchAgents/com.claude-pulse.red-alert.plist`.
Add keys inside the `<dict>` under `EnvironmentVariables`:

- If RED_ALERT_CITIES is set: `<key>RED_ALERT_CITIES</key><string>VALUE</string>`
- If RED_ALERT_MODE is set: `<key>RED_ALERT_MODE</key><string>VALUE</string>`
- If RED_ALERT_SOUND is off: `<key>RED_ALERT_SOUND</key><string>off</string>`

Also set `KeepAlive` and `RunAtLoad` to `<true/>` so the daemon auto-starts.

Then load and start:

```bash
launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist
launchctl kickstart "gui/$(id -u)/com.claude-pulse.red-alert" >/dev/null 2>&1 || true
```

Verify it's running:

```bash
launchctl list | grep claude-pulse
```

### 7. Configure SessionStart hook

Add a `SessionStart` hook to `~/.claude/settings.json` so the daemon starts automatically when Claude Code opens. Use the Edit tool to add this inside the top-level object (merge with existing hooks if any):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist; launchctl kickstart \"gui/$(id -u)/com.claude-pulse.red-alert\" >/dev/null 2>&1; true",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

The hook checks if the service is already loaded before trying to load it, avoiding errors when the daemon is already running via `RunAtLoad`.

### 8. Confirm

Tell the user:
- "Red Alert is active! 🔔 indicator should appear in your statusline."
- Show their settings (cities, sound on/off)
- "Daemon managed by launchd — survives Claude Code restarts."
- "SessionStart hook installed — daemon auto-starts with each Claude Code session."
- "To stop: `launchctl unload ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist`"
- "Restart Claude Code to pick up env var changes."
