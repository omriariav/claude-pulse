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

    # Copy the bash script
    cp claude-pulse "$CLAUDE_DIR/statusline-command.sh"
    chmod +x "$CLAUDE_DIR/statusline-command.sh"

    echo "claude-pulse installed to $CLAUDE_DIR/statusline-command.sh"
    echo ""
    echo "Next steps:"
    echo "1. Add to your Claude Code settings.json:"
    echo ""
    echo '   "statusLine": {'
    echo '     "type": "command",'
    echo '     "command": "~/.claude/statusline-command.sh"'
    echo '   }'
    echo ""
    echo "2. Restart Claude Code to see your token usage in the status line!"
fi

echo ""
echo "For more info, see: https://github.com/omriariav/claude-pulse"
