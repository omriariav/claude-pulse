# claude-pulse

> Real-time token usage monitoring for Claude Code status line | **v3.4.0**

**claude-pulse** displays your current Claude Code token usage directly in your status line, helping you stay aware of context consumption without running `/context` manually.

```
🧠 [████████░░░░░░░░░░░░] 42% · 🤖 Opus 4.6 (1M) · 💬 API Refactor · 🌿 feat/auth-flow (#12) · 📝 3 files +45 -12 · 📁 my-project
⚡ 5h: 5% · 7d:  2% · Fable:  9% · 💰  $3 · 🟢 Alerts daemon ON
```

## Features

- ✅ **Adaptive density** - Three tiers (minimal/regular/heavy) auto-detected from terminal width
- ✅ **Visual context bar** - Progress bar showing context consumed at a glance (10 or 20 chars)
- ✅ **Accurate token counting** - Reads actual usage from Claude's API responses
- ✅ **Model-aware limits** - Automatically detects context limits for different Claude models
- ✅ **Model display** - Shows which Claude model you're using (e.g., "Sonnet 4.5", "Opus 4.6")
- ✅ **Conversation names** - AI-generated short names for easy session identification
- ✅ **Git branch + PR** - Shows current branch and open PR number
- ✅ **Git diff stats** - Files changed, insertions (+green), deletions (-red) with cyan file count
- ✅ **Session cost** - Shows cumulative API cost in heavy mode (optional, for pay-per-use plans)
- ✅ **Rate limits** - 5h/7d and model-scoped Fable usage visible when available, color-coded. Note: Claude Code ≤2.1.207 does not include the Fable quota in the statusline payload (even though `/usage` shows it), so that segment stays hidden until a Claude Code release exposes it — no update needed on our side
- ✅ **Color-coded warnings** - Green → Yellow → Red as context usage increases (ANSI RGB)
- ✅ **Interactive setup** - `/setup-statusline` walks you through density, cost, and Red Alert config
- ✅ **Lightweight** - Pure bash/PowerShell script with minimal dependencies
- ✅ **Inspired by [ccusage](https://github.com/ryoppippi/ccusage)** - Uses the same accurate parsing approach

## Demo

**Heavy** (wide terminals):
```
🧠 [██░░░░░░░░░░░░░░░░░░] 10% · 🤖 Opus 4.6 (1M) · 💬 Topic Name · 🌿 feat/bar (#42) · 📝 3 files +45 -12 · 📁 project
⚡ 5h: 5% · 7d:  2% · Fable:  9% · 💰  $12 · 🟢 Alerts daemon ON
```

**Regular** (default):
```
🧠 ██░░░░░░░░ 10%  🤖 Opus 4.6 (1M)  💬 Topic Name  🌿 feat/bar (#42)  📝 3f +45 -12  📁 project
⚡ 5h: 5%  7d: 2%  Fable: 9%  🟢 Alerts ON
```

**Minimal** (narrow terminals):
```
🧠 10% Op4.6(1M) │ Topic Name │ #42 project │ 3f +45 -12 │ ⚡5h: 5% 7d: 2% Fable: 9% │ 🟢
```

**Taboola** (opt-in, slick single line — emoji-free, theme-adaptive 16-color ANSI):
```
project │ feat/bar [↑2] * │ amq:my-squad │ Op4.8 H │ 38% │ 5h:23% 7d:41% Fable:96% │ $0.42 │ 🟢
```
A compact, no-frills line modeled on a hand-rolled team statusline: last-folder dir, branch with ahead/behind + dirty marker, amq-squad team/session, short model label + reasoning **effort**, **remaining** context %, 5h/7d/Fable limits, API cost, and the alert glyph. Uses your terminal's own theme colors (not truecolor) and honors `NO_COLOR`. Enable with `CLAUDE_PULSE_DENSITY=taboola`.

Color changes based on usage:
- 🟢 **Green** (<50% used): Plenty of room
- 🟡 **Yellow** (50-79% used): Moderate usage
- 🔴 **Red** (≥80% used): Running high, consider compacting

The minimal/regular/heavy tiers auto-detect from terminal width. Override with `CLAUDE_PULSE_DENSITY=minimal|regular|heavy`, or opt into the `taboola` single-line mode (never auto-selected).

## Installation

### macOS / Linux

```bash
git clone https://github.com/omriariav/claude-pulse.git
cd claude-pulse
./install.sh
```

**Requirements**: `jq` (brew install jq / apt install jq), optionally `gh` for PR numbers

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
- **Optional**: `gh` CLI for PR number display (`brew install gh` / `apt install gh`)
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

Modern model IDs (`claude-<family>-<major>-<minor>`) are parsed generically, so
new releases like Opus 4.8 are recognized automatically — no update required.

- Claude Opus 4.8 (200k default, 1M with extended context)
- Claude Opus 4.7 / 4.6 (200k default, 1M with extended context)
- Claude Opus 4.5 (200k context)
- Claude Sonnet 4.x (200k context)
- Claude 3.5 Sonnet (200k context)
- Claude Haiku 4.5 (200k context)
- Claude Haiku 3.5 (200k context)
- Unknown models fall back to Claude Code's own `display_name`, else default to 200k

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

**Without an API key**, conversation names will be the first 3 words of the session summary or transcript (still useful!).

### How Conversation Names Work

1. **Native (v2.5.0+)** — Claude Code exposes `session_name` directly in the statusline JSON. This includes `/rename` values and auto-generated names. No API key needed.
2. **Fallback (older Claude Code)** — If `session_name` is absent, uses AI API to generate a 2-3 word name from session summary or transcript content. Cached in `~/.cache/claude-pulse/`.

After adding your API key (for fallback), restart your terminal or run `source ~/.zshrc` to apply.

### Red Alert (Pikud HaOref)

#### Setup

Run the interactive setup command inside Claude Code:

```
/setup-statusline
```

This walks you through everything: density selection, session cost toggle, city/zone selection, alert sounds, and daemon setup.

#### Update

Re-run `/setup-statusline` to change any settings. Or reinstall from the repo:

```bash
cd claude-pulse && ./install.sh
```

#### Uninstall

Run inside Claude Code:

```
/uninstall-red-alert
```

This stops the daemon, removes the launchd service, and cleans up alert settings. The base claude-pulse statusline stays installed.

#### Manual Configuration

You can also configure directly in `~/.claude/settings.json`:

```json
{
  "env": {
    "RED_ALERT_CITIES": "Tel Aviv,Ramat Gan,Jerusalem"
  }
}
```

Supports English city names, Hebrew names, zone-specific names (e.g., `Tel Aviv - City Center`), and fuzzy substring matching.

#### Environment Variables

| Variable | Values | Description |
|----------|--------|-------------|
| `CLAUDE_PULSE_DENSITY` | `minimal` / `regular` / `heavy` / `taboola` | Override auto-detected density tier (`taboola` = opt-in slick single line); all tiers show Fable quota usage when Claude Code provides it |
| `CLAUDE_PULSE_HIDE_COST` | `1` | Hide session cost (💰) in heavy/taboola mode — recommended for Max/Pro |
| `NO_COLOR` | (any) | Strip all ANSI color in `taboola` mode |
| `CLAUDE_PULSE_HIDE_DIFF` | `1` | Hide git diff stats (📝) |
| `CLAUDE_PULSE_DEBUG_RATE_LIMITS` | `1` | Write a one-shot, privacy-safe diagnostic of which `rate_limits` keys your Claude Code sends to `~/.cache/claude-pulse/rate-limits-debug.json` (capture time, Claude Code version, model id, key names only — no values, ids, or paths). Delete the file to capture again; `CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE` overrides the path |
| `RED_ALERT_CITIES` | comma-separated | Filter alerts to specific cities/zones |
| `RED_ALERT_MODE` | `all` / `mock` | `all` = every alert. `mock` = offline test data |
| `RED_ALERT_SOUND` | `off` | Disable alert sounds |
| `RED_ALERT_SOUND_COOLDOWN_MISSILE` | seconds | Min time between missile sounds (default 60) |
| `RED_ALERT_SOUND_COOLDOWN_PRE` | seconds | Min time between pre-alert sounds (default 120) |

#### Architecture

The daemon runs as a macOS LaunchAgent, managed by launchd. It auto-starts when Claude Code opens (via SessionStart hook) and self-terminates ~30s after all Claude Code instances close (heartbeat mechanism). State is stored in `~/.local/state/claude-pulse/`.

The recommended SessionStart hook command (in `~/.claude/settings.json`):

```bash
launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist; launchctl kickstart "gui/$(id -u)/com.claude-pulse.red-alert" >/dev/null 2>&1; true
```

This checks if the service is already loaded before trying to load it, avoiding errors when the daemon is already running via `RunAtLoad`.

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

## Changelog

| Version | Highlights |
|---------|-----------|
| **v3.4.0** | Optional, color-coded Fable weekly quota usage across minimal, regular, heavy, and `taboola` views, with Bash/PowerShell parity; capability-driven detection supports semantic keys, model-scope metadata, percentage/utilization payloads, and the current legacy fallback while hiding the segment when no separate quota exists |
| **v3.3.1** | `taboola` mode now resolves the amq-squad identity of the **current pane** (`amq:<profile>/<session>@<handle>`) instead of the first/default profile on disk — precedence ladder (env launch-record → tmux pane-id → env/disk session → discovery), explicit `amq:?` marker when identity can't be proven, nested `AM_ROOT` layout support, bash/PowerShell parity |
| **v3.3.0** | New opt-in `taboola` density — slick single-line, theme-adaptive 16-color ANSI, with amq-squad team/session, reasoning effort, 5h/7d limits, API cost & `NO_COLOR`; fix: statusline now always exits 0 (a non-zero exit made Claude Code render nothing) |
| **v3.2.0** | Generic model detection — new Opus/Sonnet/Haiku versions (e.g. Opus 4.8) recognized with no code change; `display_name` fallback for unknown families; CI on macos-latest |
| **v3.1.1** | KeepAlive fix, heavy mode alignment, user-level skills, OTA skill updates, setup portability |
| **v3.1.0** | Git diff stats, `CLAUDE_PULSE_HIDE_DIFF` env var, heavy mode column alignment |
| **v3.0.2** | Exponential backoff for API failures, daemon self-healing |
| **v2.5.2** | Pre-alert banner persists after main alert expires; SessionStart hook no longer kills running daemon |
| **v2.5.1** | Fix Sonnet 4.6 model detection (was showing "Sonnet 4.5") |
| **v2.5.0** | Native `session_name` support — zero-latency conversation names, no API calls needed |
| **v2.4.2** | Alert city merging across waves, per-sound-class cooldown, consolidated jq calls |
| **v2.3.x** | Two-tier alert display (active banner + recent text), Cat 10 pre-alert support |
| **v2.2.x** | Daemon singleton lock, Cat 6 = UAV fix, heartbeat keeps daemon alive during idle |
| **v2.1.x** | Rate limit display (5h/7d), sound city filtering, daemon auto-restart |
| **v2.0.0** | Red Alert (Pikud HaOref) — real-time rocket alerts, city filtering, launchd daemon |
| **v1.7.x** | Visual context bar, git branch + PR display, context window label |
| **v1.6.0** | Active session names from transcript, Opus 4.6 + 1M context support |
| **v1.5.0** | AI conversation names via Anthropic/OpenAI/Gemini |
| **v1.4.x** | Model display, dynamic context window detection |

See [RELEASE.md](RELEASE.md) for full release notes.

## Credits

### Red Alert Feature

The Red Alert feature was inspired by and built upon the work of [Liran Tal](https://github.com/lirantal) and his [red-alert-statusline](https://github.com/lirantal/red-alert-statusline) project. Liran's project pioneered the idea of bringing Pikud HaOref alerts into the Claude Code statusline, and our implementation follows many of the same architectural patterns — the two-script daemon model, the oref.org.il API integration, and the state-file approach for separating polling from display. Thank you, Liran, for the inspiration and for building tools that help keep developers in Israel safe while they work.

### Token Usage

Token usage monitoring inspired by [ccusage](https://github.com/ryoppippi/ccusage) by [@ryoppippi](https://github.com/ryoppippi).

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue or PR.

---

**Made with ❤️ for the Claude Code community**
