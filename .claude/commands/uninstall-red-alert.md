---
name: uninstall-red-alert
description: Remove Red Alert (Pikud HaOref) notifications from claude-pulse
user_invocable: true
---

# Uninstall Red Alert

Remove the Red Alert daemon, settings, and launchd service.

## Steps

### 1. Stop and remove the launchd service (macOS)

```bash
launchctl unload ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist
```

### 2. Kill any running daemon

```bash
pkill -f red-alert-daemon 2>/dev/null || true
```

### 3. Remove state files

```bash
rm -rf ~/.local/state/claude-pulse/red_alert_*
rm -rf ~/.local/state/claude-pulse/daemon.*
```

### 4. Remove alert env vars from settings.json

Use the Edit tool to remove these keys from the `env` object in `~/.claude/settings.json`:
- `RED_ALERT_CITIES`
- `RED_ALERT_MODE`
- `RED_ALERT_SOUND`
- `RED_ALERT_SOUND_COOLDOWN`
- `RED_ALERT_MOCK_INTERVAL`

Do NOT remove other env vars. Do NOT remove the `statusLine` config (claude-pulse itself stays installed).

### 5. Confirm

Tell the user:
- "Red Alert removed. The statusline will no longer show alerts."
- "claude-pulse itself is still installed — only the alert feature was removed."
- "To re-enable, run `/setup-red-alert`."
