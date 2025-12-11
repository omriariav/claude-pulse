# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-pulse is a bash script that displays real-time token usage in the Claude Code status line. It shows usage as `🧠 72k/200k (36%)` with color-coded warnings (green/yellow/red based on percentage thresholds).

## Architecture

The project consists of two bash scripts:

- **`claude-pulse`**: The main status line script that reads JSON from stdin and outputs formatted token usage
- **`install.sh`**: Installer that copies the script to `~/.claude/statusline-command.sh`

### How claude-pulse works

1. Reads JSON input from stdin (provided by Claude Code)
2. **Native mode** (Claude Code v2.0.65+): Uses `context_window` data directly from the JSON input
3. **Legacy mode** (older versions): Falls back to parsing transcript JSONL files from `transcript_path`
4. Calculates percentage and applies color coding (green <50%, yellow 50-79%, red 80%+)
5. Outputs two lines: token usage and current working directory

### Key implementation details

- Uses `jq` for JSON parsing (required dependency)
- Native mode adds `total_input_tokens + total_output_tokens` for total usage
- Legacy mode sums `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
- All supported models use 200k context limit

## Development

No build process - this is a pure bash project. To test changes:

```bash
# Test the script with sample JSON input
echo '{"cwd": "/test", "context_window": {"total_input_tokens": 50000, "total_output_tokens": 5000, "context_window_size": 200000}}' | ./claude-pulse

# Install locally
./install.sh
```

## Dependencies

- bash
- jq (JSON processor)
- `tail -r` for legacy mode (macOS; would need `tac` on Linux)
