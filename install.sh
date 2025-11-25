#!/bin/bash
# claude-pulse installation script

set -e

echo "🚀 Installing claude-pulse..."

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

# Check for required dependencies
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is required but not installed."
    echo ""
    if [[ "$OS" == "macos" ]]; then
        echo "Install with: brew install jq"
    else
        echo "Install with: sudo apt-get install jq  # or your package manager"
    fi
    exit 1
fi

# Create .claude directory if it doesn't exist
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# Copy the script
cp claude-pulse "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"

echo "✅ claude-pulse installed to $CLAUDE_DIR/statusline-command.sh"
echo ""
echo "📝 Next steps:"
echo "1. Add to your Claude Code settings.json:"
echo ""
echo '   "statusLineCommand": "~/.claude/statusline-command.sh"'
echo ""
echo "2. Restart Claude Code to see your token usage in the status line!"
echo ""
echo "📖 For more info, see: https://github.com/omriariav/claude-pulse"
