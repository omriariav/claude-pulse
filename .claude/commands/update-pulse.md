---
name: update-pulse
description: Check for claude-pulse updates and apply them
user_invocable: true
---

# Update claude-pulse

Check for new releases and apply updates.

## Steps

### 1. Show current version

Read line 2 of `~/.claude/statusline-command.sh` to extract the current version:
```bash
sed -n '2s/.*v\([0-9.]*\).*/\1/p' ~/.claude/statusline-command.sh
```

Display it to the user.

### 2. Check for staged update (notify mode)

If `~/.cache/claude-pulse/update_available` exists, a new version is already staged:
- Read the version from line 1
- Read the staging path from line 2
- Ask the user: "v{version} is staged and ready. Apply now?" using `AskUserQuestion`
- If yes: run `~/.claude/update.sh` with `CLAUDE_PULSE_AUTO_UPDATE=auto` to apply
- If no: done

### 3. Force check for updates

If no staged update, run the updater with rate limit bypass:
```bash
rm -f ~/.cache/claude-pulse/last_update_check && ~/.claude/update.sh
```

### 4. Report result

Check `~/.cache/claude-pulse/update_notification` — if it exists, the update was applied:
- Show: "Updated to v{version}!"

Check `~/.cache/claude-pulse/update_available` — notify mode:
- Show: "v{version} available. Run /update-pulse again to apply."

If neither file exists:
- Show: "Already up to date (v{current_version})"

### 5. Show changelog (optional)

If an update was applied or is available, fetch the release notes:
```bash
curl -s "https://api.github.com/repos/omriariav/claude-pulse/releases/latest" | jq -r '.body // "No changelog available"'
```

Display the changelog to the user.
