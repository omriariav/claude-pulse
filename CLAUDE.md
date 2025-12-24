# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-pulse is a bash script that displays real-time token usage in the Claude Code status line. It shows usage as `🧠 72k/200k (36%)` with color-coded warnings (green/yellow/red based on percentage thresholds).

## Architecture

The project consists of:

- **`claude-pulse`**: Main bash script for macOS/Linux
- **`claude-pulse.ps1`**: PowerShell version for Windows
- **`install.sh`**: Cross-platform installer

### How claude-pulse works

1. Reads JSON input from stdin (provided by Claude Code)
2. **Primary**: Parses transcript JSONL for `input_tokens` (billing API) - includes ALL context
3. **Fallback**: Uses native `context_window` data if transcript unavailable
4. Calculates percentage and applies color coding (green <50%, yellow 50-79%, red 80%+)
5. Outputs two lines: token usage and current working directory

### Key implementation details

- Uses `jq` for JSON parsing (macOS/Linux only)
- Billing API `input_tokens` includes: messages + system prompt + tools + MCP tools + memory
- Native `context_window` only includes conversation tokens (missing MCP/system overhead)
- >100% is normal when context exceeds limit - Claude Code will auto-compact
- All supported models use 200k context limit
- Auto-detects `tac` vs `tail -r` for Linux/macOS compatibility

## Development

No build process - pure bash/PowerShell project. To test changes:

```bash
# Test bash script (macOS/Linux)
echo '{"cwd": "/test", "context_window": {"total_input_tokens": 50000, "total_output_tokens": 5000, "context_window_size": 200000}}' | ./claude-pulse

# Install locally
./install.sh
```

## Dependencies

- **macOS/Linux**: bash, jq
- **Windows**: PowerShell (built-in)
