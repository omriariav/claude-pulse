# claude-pulse

> Real-time token usage monitoring for Claude Code status line | **v1.2**

**claude-pulse** displays your current Claude Code token usage directly in your status line, helping you stay aware of context consumption without running `/context` manually.

## New in v1.2: Accurate Billing API

**v1.2** prioritizes the billing API from transcript files for more accurate token counts. Native `context_window` data (v1.1) was found to underreport actual usage (~60% shown when context was actually full). Transcript parsing now takes priority, with native mode as fallback.

See [RELEASE.md](RELEASE.md) for full release notes.

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

### Primary: Transcript Billing API

claude-pulse reads token usage from Claude Code's transcript files (JSONL format). Each API response includes a `usage` object with billing data:

```json
{
  "input_tokens": 10,
  "cache_creation_input_tokens": 45048,
  "cache_read_input_tokens": 27423,
  "output_tokens": 313
}
```

This method provides accurate token counts that match actual context consumption.

### Fallback: Native Mode (Claude Code v2.0.65+)

If transcript parsing fails, claude-pulse falls back to native `context_window` data:

```json
{
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 4521,
    "context_window_size": 200000
  }
}
```

Note: Native mode may underreport actual usage in some scenarios.

The script:
1. Tries transcript parsing first (most accurate)
2. Falls back to native `context_window` data if transcripts unavailable
3. Calculates percentage based on the context window size
4. Returns a compact, color-coded status line

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
- claude-pulse uses API billing data from transcripts (most accurate for actual usage)
- `/context` uses Claude Code's internal estimation
- Difference is typically 2-3k tokens on a 70k total (~3%)
- The billing API data better reflects when you're actually approaching context limits

## Credits

Inspired by [ccusage](https://github.com/ryoppippi/ccusage) by [@ryoppippi](https://github.com/ryoppippi).

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue or PR.

---

**Made with ❤️ for the Claude Code community**
