# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-pulse is a bash script that displays real-time token usage in the Claude Code status line. It shows usage as `🧠 72k/200k (36%) · 🤖 Opus 4.6 · 💬 "Topic Name"` with color-coded warnings (green/yellow/red based on percentage thresholds).

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
5. Converts model ID to friendly name (e.g., "Sonnet 4.5", "Opus 4.6", "Haiku 3.5")
6. Looks up or infers a conversation name (via AI API or fallback)
7. Outputs single line: token usage, model name, conversation name, and current working directory

### Key implementation details

- Uses `jq` for JSON parsing (macOS/Linux only)
- Billing API `input_tokens` includes: messages + system prompt + tools + MCP tools + memory
- Native `context_window` only includes conversation tokens (missing MCP/system overhead)
- >100% is normal when context exceeds limit - Claude Code will auto-compact
- Context limit defaults to 200k but is dynamically overridden by `context_window.context_window_size` from JSON input (handles 1M context for Opus 4.6 etc.)
- Auto-detects `tac` vs `tail -r` for Linux/macOS compatibility

### Model detection

- Model patterns must be ordered **most specific first** in the case/switch block (e.g., `claude-opus-4-6*` before `claude-opus-4*`), otherwise more specific models match the generic pattern
- Currently supported: Opus 4.6, Opus 4.5, Sonnet 4.5, Sonnet 3.7, Sonnet 3.5, Haiku 3.5, Opus 3

### Conversation name feature

- **Two sources**: (1) session summary from `sessions-index.json` (set by `/rename` or conversation end), (2) first 3 assistant messages from the transcript JSONL (for active sessions)
- **AI API providers**: Tries Anthropic → OpenAI → Gemini in order; falls back to first 3 words if no API available
- **Caching**: Names cached in `~/.cache/claude-pulse/{session_id}.name` with MD5 hash of source text for invalidation
- **Key learning**: `sessions-index.json` only gets populated after a session ends or user runs `/rename` — for active sessions, the transcript fallback is essential
- **Transcript structure**: User-typed prompts are NOT stored as plain text in `type: "user"` entries (those are mostly tool results). The `type: "assistant"` entries with `content[].type == "text"` contain the best topic signals
- API call logic is extracted into reusable functions (`generate_name_via_api` in bash, `Get-ConversationName` in PowerShell) to avoid duplication

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
