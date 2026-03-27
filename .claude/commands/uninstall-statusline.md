---
name: uninstall-statusline
description: Remove claude-pulse statusline completely — scripts, daemon, settings, hooks
user_invocable: true
---

# Uninstall claude-pulse

Remove everything: statusline, daemon, settings, hooks.

## 1. Stop and remove daemon (macOS)

```bash
launchctl unload ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist
pkill -f red-alert-daemon 2>/dev/null || true
```

## 2. Remove state files

```bash
rm -rf ~/.local/state/claude-pulse/
rm -rf ~/.cache/claude-pulse/
```

## 3. Remove installed scripts

```bash
rm -f ~/.claude/statusline-command.sh
rm -f ~/.claude/red-alert-daemon.sh
rm -f ~/.claude/districts_eng.json
rm -rf ~/.claude/static/*.m4a
```

## 4. Clean settings.json

Read `~/.claude/settings.json`, then Edit to remove:

- `statusLine` key entirely
- From `env` object: `RED_ALERT_CITIES`, `RED_ALERT_MODE`, `RED_ALERT_SOUND`, `RED_ALERT_SOUND_COOLDOWN`, `RED_ALERT_MOCK_INTERVAL`, `CLAUDE_PULSE_DENSITY`
- From `hooks.SessionStart`: remove any hook entry containing `com.claude-pulse.red-alert`

Do NOT remove other env vars, hooks, or settings.

## 5. Confirm

Tell the user:
- "claude-pulse fully removed."
- "Restart Claude Code to clear the statusline."
- "To reinstall: clone the repo and run `/setup-statusline`."
