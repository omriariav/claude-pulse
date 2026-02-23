# Release Notes

## v1.7.0 - Context Bar, Branch/PR, Cleaner Topic UX

**Released:** February 23, 2026

### What's New

- **Visual context bar**: 20-character progress bar shows context **consumed** — bar fills up as you use more context, color shifts from green to yellow to red
- **Git branch + PR number**: Shows current branch (e.g., `🌿 feat/bar`) and open PR number (e.g., `🌿 fix/auth (#42)`) with 10-minute caching to avoid slow API calls
- **Cleaner topic names**: Removed noisy quotes around conversation names, added 20-char truncation with `..` for long names

### Display Format

Before (v1.6.0):
```
🧠 64k/200k (32%) · 🤖 Opus 4.6 · 💬 "Topic Name" 📁 ~/Code/project
```

After (v1.7.0):
```
🧠 [██████░░░░░░░░░░░░░░] 32% · 🤖 Opus 4.6 · 💬 Topic Name · 🌿 feat/bar 📁 ~/Code/project
```

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
```

---

## v1.6.0 - Active Session Names & Opus 4.6

**Released:** February 6, 2026

### What's New

- **Active session names**: Conversation names now appear from the first message — for sessions without a `/rename` summary, the script infers a topic from the first few assistant messages in the transcript
- **Opus 4.6 detection**: Correctly identifies `claude-opus-4-6` model ID and displays "Opus 4.6" in the statusline
- **1M context ready**: Dynamic detection handles Opus 4.6's extended context window automatically

### Changes

- Added transcript-based fallback for conversation name inference when no session summary exists
- Refactored AI API call logic into reusable functions (`generate_name_via_api` in bash, `Get-ConversationName` in PowerShell)
- Added `claude-opus-4-6*` pattern before the generic `claude-opus-4*` case in both scripts

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
```

---

## v1.4.1 - Dynamic Context Window Detection

**Released:** January 5, 2026

### What's New

- **Dynamic context limits**: Automatically reads actual context window size from Claude Code (200k, 1M, etc.)
- **Accurate for all models**: No longer hardcoded to 200k - works with extended context models
- **Mid-conversation updates**: Correctly handles model switches during active conversations

### Bug Fixes

- Fixed issue where statusline would revert to 200k after first message in conversations using 1M context models
- Context limit now properly updates when switching between models with different context windows

## v1.4.0 - Model Display & Single-Line Output

**Released:** December 25, 2025

### What's New

- **Model display**: Shows which Claude model you're using (e.g., "Sonnet 4.5", "Opus 4.5", "Haiku 3.5")
- **Single-line output**: Token usage, model name, and working directory all on one compact line
- **Better UX**: More information in less vertical space

### Display Format

Before:
```
🧠 72k/200k (36%)
📁 /Users/you/project
```

After:
```
🧠 72k/200k (36%) · Sonnet 4.5 📁 /Users/you/project
```

### Why This Change?

Based on user feedback, the two-line format took up too much vertical space in the status line. The new single-line format provides more information (including which model you're using) while being more compact.

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
```

For Windows users, re-copy `claude-pulse.ps1` to your `.claude` folder.

---

## v1.3.1 - Accurate Full Context Usage

**Released:** December 24, 2025

### What's New

- **Windows support**: Native PowerShell script (`claude-pulse.ps1`) for Windows users
- **Linux support**: Auto-detection of `tac` vs `tail -r` for transcript parsing
- **Accurate context display**: Shows FULL context usage matching `/context` command

### Why This Change?

v1.3.0 incorrectly prioritized native `context_window` which only shows conversation tokens, missing critical overhead:
- System prompt (~3k tokens)
- System tools (~15k tokens)
- MCP tools (can be 50-100k+ tokens!)
- Memory files

This caused claude-pulse to show ~88% when `/context` showed 124%. The billing API's `input_tokens` field includes ALL context, matching what `/context` displays.

**>100% is not a bug** - it means your context has exceeded the limit and Claude Code will auto-compact.

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
```

For Windows users, see README for PowerShell installation instructions.

---

## v1.3.0 - Windows Support (Superseded by v1.3.1)

**Released:** December 24, 2025

This version incorrectly prioritized native `context_window` data. Use v1.3.1 instead.

---

## v1.2.0 - Prefer Billing API for Accuracy

**Released:** December 11, 2025

### What's New

Native `context_window` data was found to underreport actual context usage (~60% shown when context was actually full). v1.2 reverses the priority: transcript parsing (billing API) is now primary, with native mode as fallback.

### Changes

- **Billing API first**: Transcript parsing is now the primary method for accurate token counts
- **Native as fallback**: `context_window` data is used only when transcripts are unavailable
- **Added CLAUDE.md**: Project guidance for Claude Code

### Why This Change?

Testing revealed that native `context_window` data could show ~60% usage when the context was actually full. The billing API from transcripts (summing `input_tokens`, `cache_creation_input_tokens`, and `cache_read_input_tokens`) provides more accurate counts that reflect actual context consumption.

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
```

---

## v1.1.0 - Native Context Window Support

**Released:** December 11, 2025

### What's New

Claude Code v2.0.65 introduced native `context_window` data in the status line JSON input. claude-pulse now uses this data directly instead of parsing transcript files.

### Changes

- **Native mode**: Automatically uses `context_window` data when available (Claude Code v2.0.65+)
- **Backward compatible**: Falls back to transcript parsing for older Claude Code versions
- **Simpler & faster**: No file I/O needed in native mode
- **More accurate**: Uses the same data source as `/context` command

### How It Works

Claude Code now provides context data directly:

```json
{
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 4521,
    "context_window_size": 200000
  }
}
```

The script detects if this data is present and uses it automatically.

### Upgrade

Just pull the latest version:

```bash
cd claude-pulse
git pull
./install.sh
```

---

## v1.0.0 - Initial Release

**Released:** November 25, 2024

- Real-time token usage monitoring
- Color-coded warnings (green/yellow/red)
- Transcript-based token counting
- Inspired by [ccusage](https://github.com/ryoppippi/ccusage)
