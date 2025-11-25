# claude-pulse

> Real-time token usage monitoring for Claude Code status line

**claude-pulse** displays your current Claude Code token usage directly in your status line, helping you stay aware of context consumption without running `/context` manually.

![claude-pulse in action](screenshot.png)

## Features

- ✅ **Accurate token counting** - Reads actual usage from Claude's API responses
- ✅ **Model-aware limits** - Automatically detects context limits for different Claude models
- ✅ **Compact display** - Shows usage as `🧠 72k/200k (36%)` in your status line
- ✅ **Color-coded warnings** - Green → Yellow → Red as you approach context limits
- ✅ **Lightweight** - Pure bash script with minimal dependencies
- ✅ **Inspired by [ccusage](https://github.com/ryoppippi/ccusage)** - Uses the same accurate parsing approach

## Demo

```
🧠 72k/200k (36%)
📁 /Users/you/Code/your-project
```

**First line**: Token usage (current/limit) and percentage
**Second line**: Current working directory where Claude Code was executed

Color changes based on usage:
- 🟢 **Green** (0-49%): Plenty of context remaining
- 🟡 **Yellow** (50-79%): Moderate usage
- 🔴 **Red** (80-100%): High usage, consider compacting

## Installation

### Quick Install

```bash
git clone https://github.com/omriariav/claude-pulse.git
cd claude-pulse
./install.sh
```

### Manual Install

1. Copy `claude-pulse` to `~/.claude/statusline-command.sh`:
   ```bash
   cp claude-pulse ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. Add to your Claude Code `settings.json`:
   ```json
   {
     "statusLineCommand": "~/.claude/statusline-command.sh"
   }
   ```

3. Restart Claude Code

## Requirements

- **Claude Code** (obviously!)
- **jq** - JSON parser
  - macOS: `brew install jq`
  - Linux: `sudo apt-get install jq`

## How It Works

claude-pulse reads token usage data from Claude Code's transcript files (JSONL format). Each time Claude's API responds, it includes a `usage` object with:

```json
{
  "input_tokens": 10,
  "cache_creation_input_tokens": 45048,
  "cache_read_input_tokens": 27423,
  "output_tokens": 313
}
```

The script:
1. Reads the latest API response from the transcript
2. Sums all **input token types** (input + cache_creation + cache_read)
3. Excludes output tokens (they don't count toward context limit)
4. Calculates percentage based on the model's context window
5. Returns a compact, color-coded status line

This is the **actual billing data** from Anthropic's API, not an estimation.

## Supported Models

- Claude Sonnet 4.x (200k context)
- Claude Opus 4 (200k context)
- Claude 3.5 Sonnet (200k context)
- Claude Haiku 3.5 (200k context)
- Unknown models default to 200k

## Configuration

The script automatically detects your model and sets the appropriate context limit. No configuration needed!

## Why Not Use /context?

You can! But claude-pulse offers:
- **Always visible** - No need to run `/context` manually
- **API accuracy** - Uses actual billing data from Claude
- **Lightweight** - No parsing of command output needed
- **Automatic** - Updates with every message

The difference between claude-pulse and `/context` is typically <3% (negligible).

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

**~3% difference from /context**
- claude-pulse uses actual API billing data (what Anthropic charges)
- `/context` uses Claude Code's estimation
- Difference is typically 2-3k tokens on a 70k total (~3%)
- This is due to timing (when snapshots are taken) and minor calculation differences
- For practical purposes, the difference is negligible
- If you need exact `/context` numbers, that tool remains available

## Credits

Inspired by [ccusage](https://github.com/ryoppippi/ccusage) by [@ryoppippi](https://github.com/ryoppippi).

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue or PR.

---

**Made with ❤️ for the Claude Code community**
