# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-pulse is a bash script that displays real-time token usage in the Claude Code status line with adaptive density (minimal/regular/heavy) that auto-detects terminal width. Color-coded warnings (green/yellow/red based on percentage thresholds).

## Architecture

The project consists of:

- **`claude-pulse`**: Main bash script for macOS/Linux
- **`claude-pulse.ps1`**: PowerShell version for Windows
- **`red-alert-daemon.sh`**: Background daemon for Pikud HaOref alert polling
- **`install.sh`**: Cross-platform installer
- **`tests/`**: Test suite (run with `bash tests/run_tests.sh`)

### How claude-pulse works

1. Reads JSON input from stdin (provided by Claude Code)
2. **Primary**: Parses transcript JSONL for `input_tokens` (billing API) - includes ALL context
3. **Fallback**: Uses native `context_window` data if transcript unavailable
4. Calculates percentage and applies color coding (green <50%, yellow 50-79%, red 80%+)
5. Converts model ID to friendly name (e.g., "Sonnet 4.5", "Opus 4.6", "Haiku 3.5")
6. Looks up or infers a conversation name (via AI API or fallback)
7. Outputs density-aware statusline (minimal: 1 line, regular/heavy: 2 lines)

### Key implementation details

- Uses `jq` for JSON parsing (macOS/Linux only)
- Billing API `input_tokens` includes: messages + system prompt + tools + MCP tools + memory
- Native `context_window` only includes conversation tokens (missing MCP/system overhead)
- >100% is normal when context exceeds limit - Claude Code will auto-compact
- Context limit defaults to 200k but is dynamically overridden by `context_window.context_window_size` from JSON input (handles 1M context for Opus 4.6 etc.)
- Auto-detects `tac` vs `tail -r` for Linux/macOS compatibility
- ANSI RGB color palette using `$'...'` bash literals (not double-quoted `"\033..."`)

### Adaptive density (v3.0.0)

Three tiers auto-detected from terminal width, overridable with `CLAUDE_PULSE_DENSITY` env var:

- **Minimal** (< 100 cols): Single line, `│` separators, no bar, abbreviated model (`Son4.6`), rates + alerts inline
- **Regular** (100–159 cols): Two lines, emoji dividers (double-space), 10-char bare bar, `%2d` rate padding for alignment
- **Heavy** (≥ 160 cols): Two lines, ` · ` dot separators, 20-char bracketed bar, full branch, `~/` path, optional session cost

Key alignment rules for regular mode:
- Line 2 uses `%2d` for 5h rate and `%3d` for 7d rate so `🟢` lands under `🤖`
- The `·` before `🟢` stacks with the `·` after context `%` on line 1

Env vars: `CLAUDE_PULSE_DENSITY` (minimal/regular/heavy), `CLAUDE_PULSE_HIDE_COST` (set to hide `💰` in heavy mode — recommended for Max/Pro users)

### Model detection

- Model patterns must be ordered **most specific first** in the case/switch block (e.g., `claude-opus-4-6*` before `claude-opus-4*`), otherwise more specific models match the generic pattern
- Currently supported: Opus 4.6, Opus 4.5, Sonnet 4.5, Sonnet 3.7, Sonnet 3.5, Haiku 3.5, Opus 3

### Conversation name feature

- **Primary: native `session_name`**: Claude Code exposes `session_name` in the statusline JSON input (set by `/rename` or auto-generated). Used directly when present — zero API calls, no caching needed.
- **Fallback (older Claude Code)**: When `session_name` is absent, falls back to: (1) session summary from `sessions-index.json`, (2) first 3 assistant messages from the transcript JSONL
- **AI API providers** (fallback only): Tries Anthropic → OpenAI → Gemini in order; falls back to first 3 words if no API available
- **Caching** (fallback only): Names cached in `~/.cache/claude-pulse/{session_id}.name` with MD5 hash of source text for invalidation
- **Key learning**: `sessions-index.json` only gets populated after a session ends or user runs `/rename` — for active sessions, the transcript fallback is essential
- **Transcript structure**: User-typed prompts are NOT stored as plain text in `type: "user"` entries (those are mostly tool results). The `type: "assistant"` entries with `content[].type == "text"` contain the best topic signals
- API call logic is extracted into reusable functions (`generate_name_via_api` in bash, `Get-ConversationName` in PowerShell) to avoid duplication

### Red Alert feature

- **Two-script architecture**: `red-alert-daemon.sh` polls the Pikud HaOref API in the background, writes state to `/tmp/red_alert_state.json`. `claude-pulse` reads this file (no network I/O in statusline).
- **Auto-start**: Daemon launches automatically when `RED_ALERT_CITIES` or `RED_ALERT_MODE` is set. PID tracked at `/tmp/red_alert_daemon.pid`.
- **City mapping**: English→Hebrew mapping uses a `case` statement (not `declare -A`) for bash 3.2 compatibility on macOS.
- **Alert persistence**: Active alerts shown for 60s, pre-alerts for 20min, all-clear for 15s after last detection.
- **Mock mode**: `RED_ALERT_MODE=mock` cycles through fake alerts for testing without API calls.
- **Testable paths**: `RED_ALERT_STATE_FILE` and `RED_ALERT_PID_FILE` env vars override defaults for isolated testing.

## Development

No build process - pure bash/PowerShell project. To test changes:

```bash
# Test bash script with full JSON input (model, transcript, session)
echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"session_id":"SESSION_ID","transcript_path":"PATH_TO_JSONL","context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | ./claude-pulse

# Quick test without conversation name (minimal JSON)
echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | ./claude-pulse

# Install locally
./install.sh
# Or manually: cp claude-pulse ~/.claude/statusline-command.sh

# Run tests
bash tests/run_tests.sh

# Test with mock alerts
RED_ALERT_MODE=mock echo '{"cwd":"/test","model":{"id":"claude-opus-4-6"},"context_window":{"total_input_tokens":50000,"total_output_tokens":5000,"context_window_size":200000}}' | ./claude-pulse
```

### Version bumping checklist

When releasing a new version, update ALL of these files:
1. `claude-pulse` line 2 — version comment
2. `claude-pulse.ps1` line 1 — version comment
3. `README.md` — version badge, "New in vX.Y.Z" section, move previous version to "Previous Updates"
4. `RELEASE.md` — add new release entry at the top
5. Install: `cp claude-pulse ~/.claude/statusline-command.sh`

## Dependencies

- **macOS/Linux**: bash, jq, curl (for AI API calls)
- **Windows**: PowerShell (built-in)

## Statusline JSON schema

Claude Code provides these fields to the statusline command via stdin:

```
session_id, transcript_path, cwd, model.id, model.display_name,
workspace, version, cost, context_window (total_input_tokens,
total_output_tokens, context_window_size)
```

**Not available**: effort/thinking level, conversation name — these are not exposed by Claude Code in the statusline JSON.
