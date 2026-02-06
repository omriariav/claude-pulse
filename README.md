# claude-pulse

> Real-time token usage monitoring for Claude Code status line | **v1.5.1**

**claude-pulse** displays your current Claude Code token usage directly in your status line, helping you stay aware of context consumption without running `/context` manually.

## New in v1.5.1: Opus 4.6 Support

- **Opus 4.6 detection** - Correctly identifies `claude-opus-4-6` as "Opus 4.6" in the statusline
- **1M context ready** - Dynamic detection handles Opus 4.6's extended context window automatically

## Previous Updates

### v1.5.0: Conversation Names & Multi-Provider API Support

- **Conversation names** - Shows AI-generated short names for each conversation (e.g., "Statusline Names")
- **Multi-provider API** - Supports Anthropic, OpenAI, and Gemini APIs for name generation
- **Smart fallback** - Extracts first 3 words from summary if no API key configured
- **Visual clarity** - Added emojis (🤖 for model, 💬 for conversation) to distinguish elements

### v1.4.1: Dynamic Context Window Detection
- **Dynamic context limits** - Automatically detects and displays correct context window size (200k, 1M, etc.)
- **Mid-conversation updates** - Correctly updates when switching models during a conversation

### v1.4.0: Model Display
- **Model display** - Shows current model in use (e.g., "Sonnet 4.5", "Opus 4.5", "Haiku 3.5")
- **Single-line output** - Token usage, model name, and working directory on one compact line
- **Accurate display** - Shows FULL context usage matching `/context` command (including MCP tools, system prompt, etc.)

**Note:** >100% is normal when context exceeds the limit - Claude Code will auto-compact.

See [RELEASE.md](RELEASE.md) for full release notes.

![claude-pulse in action](screenshot.png)

## Features

- ✅ **Accurate token counting** - Reads actual usage from Claude's API responses
- ✅ **Model-aware limits** - Automatically detects context limits for different Claude models
- ✅ **Model display** - Shows which Claude model you're using (e.g., "Sonnet 4.5", "Opus 4.5")
- ✅ **Conversation names** - AI-generated short names for easy session identification
- ✅ **Multi-provider API** - Works with Anthropic, OpenAI, or Gemini API keys
- ✅ **Compact display** - Single line showing usage, model, conversation, and directory
- ✅ **Color-coded warnings** - Green → Yellow → Red as you approach context limits
- ✅ **Lightweight** - Pure bash/PowerShell script with minimal dependencies
- ✅ **Inspired by [ccusage](https://github.com/ryoppippi/ccusage)** - Uses the same accurate parsing approach

## Demo

```
🧠 72k/200k (36%) · 🤖 Sonnet 4.5 · 💬 "Statusline Names" 📁 /Users/you/Code/your-project
```

Displays token usage (current/limit), percentage, current model, conversation name, and working directory all on one compact line.

Color changes based on usage:
- 🟢 **Green** (0-49%): Plenty of context remaining
- 🟡 **Yellow** (50-79%): Moderate usage
- 🔴 **Red** (80-100%): High usage, consider compacting

## Installation

### macOS / Linux

```bash
git clone https://github.com/omriariav/claude-pulse.git
cd claude-pulse
./install.sh
```

**Requirements**: `jq` (brew install jq / apt install jq)

### Windows (PowerShell)

1. Clone or download the repository
2. Copy `claude-pulse.ps1` to your `.claude` folder:
   ```powershell
   Copy-Item claude-pulse.ps1 "$env:USERPROFILE\.claude\statusline-command.ps1"
   ```

3. Add to your Claude Code `settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "powershell -ExecutionPolicy Bypass -File C:/Users/YOUR_USERNAME/.claude/statusline-command.ps1"
     }
   }
   ```

4. Restart Claude Code

### Manual Install (macOS/Linux)

1. Copy `claude-pulse` to `~/.claude/statusline-command.sh`:
   ```bash
   cp claude-pulse ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. Add to your Claude Code `settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline-command.sh"
     }
   }
   ```

3. Restart Claude Code

## Requirements

- **Claude Code** (obviously!)
- **macOS/Linux**: `jq` JSON parser
  - macOS: `brew install jq`
  - Linux: `sudo apt-get install jq`
- **Windows**: PowerShell (included in Windows)

## How It Works

### Primary: Billing API via Transcript (Most Accurate)

claude-pulse reads usage data from Claude's transcript files (JSONL format) which contain the actual billing API response. This includes:
- Message tokens
- System prompt tokens
- Tool definitions (including MCP tools)
- Memory files
- All context overhead

This matches what `/context` shows - the FULL context usage.

### Fallback: Native Context Window

If transcript data is unavailable, claude-pulse falls back to the native `context_window` data from Claude Code:

```json
{
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 4521,
    "context_window_size": 200000
  }
}
```

The script:
1. Tries to read billing API data from transcript (most accurate)
2. Falls back to native `context_window` if transcript unavailable
3. Extracts and converts model ID to friendly name
4. Calculates percentage and applies color coding
5. Returns a compact, single-line status display

## Supported Models

- Claude Opus 4.6 (200k default, 1M with extended context)
- Claude Opus 4.5 (200k context)
- Claude Sonnet 4.x (200k context)
- Claude 3.5 Sonnet (200k context)
- Claude Haiku 3.5 (200k context)
- Unknown models default to 200k

## Configuration

### API Keys (Optional - For Conversation Names)

To enable AI-generated conversation names, set one of these environment variables in your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
# Option 1: Anthropic (uses Claude Haiku 4.5)
export ANTHROPIC_API_KEY=sk-ant-...

# Option 2: OpenAI (uses GPT-4o Mini)
export OPENAI_API_KEY=sk-...

# Option 3: Google Gemini (uses Gemini 2.5 Flash)
export GEMINI_API_KEY=...
```

The script tries APIs in this order: Anthropic → OpenAI → Gemini → Fallback (first 3 words).

**Without an API key**, conversation names will be the first 3 words of the session summary (still useful!).

After adding your API key, restart your terminal or run `source ~/.zshrc` to apply.

### Model Detection

The script automatically detects your model and sets the appropriate context limit. No additional configuration needed!

## Why Not Use /context?

You can! But claude-pulse offers:
- **Always visible** - No need to run `/context` manually
- **More accurate** - Uses billing API data which reflects actual context consumption
- **Automatic** - Updates with every message
- **Color-coded** - Visual warnings as you approach limits

## Troubleshooting

**Status line shows "No token usage yet"**
- This is normal for new sessions before the first API response
- Wait for Claude's first response

**Script not running**
- Verify `~/.claude/statusline-command.sh` exists and is executable
- Check that `jq` is installed: `which jq`
- Restart Claude Code after configuration changes

**Token count seems off**
- claude-pulse reads from transcript files, which update after each API response
- Small differences (<3%) from `/context` are normal due to timing

## Known Issues

**Small differences from /context**
- Difference is typically 2-3k tokens (~3%)
- Both use context window data, but timing of updates may differ slightly

## Credits

Inspired by [ccusage](https://github.com/ryoppippi/ccusage) by [@ryoppippi](https://github.com/ryoppippi).

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue or PR.

---

**Made with ❤️ for the Claude Code community**
