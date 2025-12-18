# Release Notes

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
