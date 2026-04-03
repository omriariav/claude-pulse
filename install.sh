#!/bin/bash
# claude-pulse installation script

set -e

echo "Installing claude-pulse..."

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
    OS="windows"
else
    echo "Unsupported OS: $OSTYPE"
    echo "For Windows, run this from Git Bash or see README for PowerShell instructions."
    exit 1
fi

# Create .claude directory if it doesn't exist
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# Download Hebrew→English city/district mapping for Red Alert
DISTRICTS_URL="https://www.oref.org.il/districts/districts_eng.json"
DISTRICTS_FILE="$CLAUDE_DIR/districts_eng.json"
echo "Downloading district translations..."
if curl -sf --max-time 10 -o "$DISTRICTS_FILE" "$DISTRICTS_URL" 2>/dev/null && jq empty "$DISTRICTS_FILE" 2>/dev/null; then
    echo "Districts file saved to $DISTRICTS_FILE ($(jq length "$DISTRICTS_FILE") entries)"
else
    rm -f "$DISTRICTS_FILE"
    echo "Warning: Could not download districts file. English city names will not be available."
fi

if [[ "$OS" == "windows" ]]; then
    # Windows: Install PowerShell script
    cp claude-pulse.ps1 "$CLAUDE_DIR/statusline-command.ps1"

    # Convert path to Windows format
    WIN_PATH=$(cygpath -w "$CLAUDE_DIR/statusline-command.ps1" 2>/dev/null || echo "$CLAUDE_DIR/statusline-command.ps1")

    echo "claude-pulse installed to $CLAUDE_DIR/statusline-command.ps1"
    echo ""
    echo "Next steps:"
    echo "1. Add to your Claude Code settings.json:"
    echo ""
    echo "   \"statusLine\": {"
    echo "     \"type\": \"command\","
    echo "     \"command\": \"powershell -ExecutionPolicy Bypass -File $WIN_PATH\""
    echo "   }"
    echo ""
    echo "2. Restart Claude Code to see your token usage in the status line!"
else
    # macOS/Linux: Check for jq dependency
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed."
        echo ""
        if [[ "$OS" == "macos" ]]; then
            echo "Install with: brew install jq"
        else
            echo "Install with: sudo apt-get install jq  # or your package manager"
        fi
        exit 1
    fi

    # Copy the bash script, daemon, and updater
    cp claude-pulse "$CLAUDE_DIR/statusline-command.sh"
    chmod +x "$CLAUDE_DIR/statusline-command.sh"
    cp red-alert-daemon.sh "$CLAUDE_DIR/red-alert-daemon.sh"
    chmod +x "$CLAUDE_DIR/red-alert-daemon.sh"
    cp update.sh "$CLAUDE_DIR/update.sh"
    chmod +x "$CLAUDE_DIR/update.sh"
    mkdir -p "$CLAUDE_DIR/static" "$CLAUDE_DIR/commands"
    cp static/*.m4a "$CLAUDE_DIR/static/" 2>/dev/null || true
    for skill in setup-statusline update-pulse uninstall-statusline uninstall-red-alert; do
        cp ".claude/commands/${skill}.md" "$CLAUDE_DIR/commands/${skill}.md" 2>/dev/null || true
    done

    echo "claude-pulse installed to $CLAUDE_DIR/statusline-command.sh"
    echo "red-alert-daemon installed to $CLAUDE_DIR/red-alert-daemon.sh"
    echo "update.sh installed to $CLAUDE_DIR/update.sh"
    echo ""

    # Configure statusline in settings.json
    SETTINGS_FILE="$CLAUDE_DIR/settings.json"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
    fi

    # Configure statusline + OTA hooks in settings.json (merge, don't clobber)
    if command -v jq &>/dev/null; then
        tmp_settings="${SETTINGS_FILE}.$$"

        # Add statusLine command
        jq '.statusLine = {"type": "command", "command": "~/.claude/statusline-command.sh"}' \
            "$SETTINGS_FILE" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_FILE"

        # Add SessionStart hooks (OTA update check + daemon restart marker)
        # Merge with existing hooks — don't clobber user's custom hooks
        UPDATE_HOOK="~/.claude/update.sh >/dev/null 2>&1 &"
        RESTART_HOOK="if [ -f ~/.local/state/claude-pulse/daemon_restart_requested ]; then rm -f ~/.local/state/claude-pulse/daemon_restart_requested; launchctl kickstart -k gui/\$(id -u)/com.claude-pulse.red-alert 2>/dev/null; fi"

        jq --arg update_hook "$UPDATE_HOOK" --arg restart_hook "$RESTART_HOOK" '
            # Ensure hooks.SessionStart exists as an array
            .hooks.SessionStart //= [] |
            # Add update hook if not already present (nested hooks format required by schema)
            if (.hooks.SessionStart | map(select(.hooks[]?.command == $update_hook)) | length) == 0 then
                .hooks.SessionStart += [{"hooks": [{"type": "command", "command": $update_hook, "timeout": 5}]}]
            else . end |
            # Add restart hook if not already present
            if (.hooks.SessionStart | map(select(.hooks[]?.command == $restart_hook)) | length) == 0 then
                .hooks.SessionStart += [{"hooks": [{"type": "command", "command": $restart_hook, "timeout": 5}]}]
            else . end
        ' "$SETTINGS_FILE" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_FILE"

        echo "Statusline configured in settings.json"
        echo "OTA update hooks registered"
    fi

    # Update preference
    echo ""
    echo "Update mode:"
    echo "  auto   — Updates applied automatically on session start (default)"
    echo "  notify — Show badge when update available, apply manually with /update-pulse"
    echo ""
    read -rp "Update mode [auto]: " update_mode
    update_mode="${update_mode:-auto}"
    if [[ "$update_mode" == "notify" ]]; then
        if command -v jq &>/dev/null; then
            tmp_settings="${SETTINGS_FILE}.$$"
            jq '.env.CLAUDE_PULSE_AUTO_UPDATE = "notify"' "$SETTINGS_FILE" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_FILE"
            echo "Update mode set to: notify"
        fi
    else
        echo "Update mode set to: auto (default)"
    fi

    # macOS: install launchd service for the daemon
    if [[ "$OS" == "macos" ]]; then
        PLIST_LABEL="com.claude-pulse.red-alert"
        PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
        DAEMON_PATH="$CLAUDE_DIR/red-alert-daemon.sh"
        LOG_DIR="$HOME/.local/state/claude-pulse"
        mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"

        cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DAEMON_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/daemon.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/daemon.stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLIST
        echo "LaunchAgent installed to $PLIST_FILE"
        echo ""
        echo "Daemon commands:"
        echo "  Start:  launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist"
        echo "  Stop:   launchctl unload ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist"
        echo "  Status: launchctl list | grep claude-pulse"
    fi

    echo ""
    echo "To customize density, cost display, and Red Alert:  /setup-statusline"
    echo "Or just start using Claude Code — the statusline works immediately."
fi

echo ""
echo "For more info, see: https://github.com/omriariav/claude-pulse"
