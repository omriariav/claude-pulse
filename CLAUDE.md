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
- **Heavy** (≥ 160 cols): Two lines, ` · ` dot separators, 20-char bracketed bar, full branch, optional session cost
- **Taboola** (opt-in only, never auto-detected): Single line, dim `│` separators, mimics `taboola-sales-skills/.claude/statusline.sh` (blue last-folder-only dir via `short_cwd`, green branch + yellow `[↑n ↓n]` ahead/behind + `*`/`+` dirty marker, cyan short model label `model_short` e.g. `Op4.8`). Deliberately emoji-free (matches the reference's slick look) — plain colored tokens only. Uses the reference's exact palette: **standard 16-color ANSI** (`\033[34m` blue, `32` green, `33` yellow, `35` magenta, `36` cyan, `31` red, `\033[2m` dim) — theme-adaptive, *not* claude-pulse's truecolor RGB — and honors **`NO_COLOR`** (taboola branch only; the other densities keep their RGB palette). Enriched with claude-pulse data: **amq-squad** identity for the *current pane* (`amq:<profile>/<session>@<handle>`, e.g. `amq:codex-v2-11-0/v2-11-0@developer`; profile is omitted when it equals the session, so `foo/foo@dev` collapses to `amq:foo@dev`; dim `amq:n/a` when `amq` is installed but the project isn't a squad; yellow `amq:?` when a squad context exists but the active profile can't be proven), model **effort** (magenta, abbreviated `low→L medium→M high→H xhigh→XH max→MAX`), context **remaining %** (health-colored red ≤20 / yellow ≤40 / green, billing-accurate `100 - percent`), **5h/7d/Fable** rate limits (`5h:23% 7d:41% Fable:96%`, health-colored red ≥80 / yellow ≥50 / green), **API cost** (`$0.42`, cents precision, neutral default-fg — cost isn't a health signal), and the **red-alert** indicator (idle daemon compacts to a bare glyph; a live alert keeps its full banner). Fable is capability-detected and omitted when Claude Code does not advertise a separate quota. Respects `CLAUDE_PULSE_HIDE_COST`. Set via `CLAUDE_PULSE_DENSITY=taboola`.
  - **amq-squad detection** (`_resolve_amq_identity`): resolves the **current pane's** profile/session/handle rather than the first profile found on disk — earlier versions read `.workstream` from the nearest `.amq-squad/team.json` (the *default* profile) and so mislabeled panes launched from a *named* profile (e.g. showed the stale default workstream `v1-0-0-reshape` instead of `codex-v2-11-0/v2-11-0`). Precedence ladder (highest first):
    1. **Current env + launch record.** `AM_ROOT` + `AM_ME` point straight at this agent's dir (`$AM_ROOT/agents/$AM_ME`); the amq-squad `launch.json` there (under `extensions/io.github.omriariav.amq-squad/`, or bare) carries the authoritative `team_profile` (null → `default`), `session`, and `handle`. `AM_ROOT` is normalized to absolute (amq may export it relative). When `AM_ME` is absent, this session's agent dirs are matched by tmux pane id (`$TMUX_PANE` vs `.tmux.pane_id`).
    2. **Launch metadata by pane id.** With no `AM_ROOT`, `launch.json` files under the base root are matched to `$TMUX_PANE`.
    - **Pane-id liveness guard (`_amq_launch_alive`, issue #48).** tmux recycles pane ids after panes close, so *both* pane-id match paths above (the tier-1 loop and tier-2) require the record's `agent_pid` to still be alive (`kill -0` — a signal-free existence probe) before trusting the match. A dead pid means the pane id was recycled from a long-gone agent (e.g. a plain session landing in a former squad tree), so the record is skipped rather than shown as the current pane's identity — resolution then degrades honestly to tier 3/4 (`amq:?`/`amq:n/a`). Records from older amq without `agent_pid` keep prior behavior (can't disprove → trust the pane match). The env fast path (tier 1, `AM_ROOT`+`AM_ME`) is **not** gated — it reads *this* process's own env, so it needs no liveness proof. Residual edge (PID reuse *and* pane-id reuse coinciding on one record) is left unguarded; a `started_at` cross-check is the noted follow-up.
    3. **Env/amq-derived session.** `session` = `basename $AM_ROOT`, else `amq env --session-name`; the owning profile is disambiguated from disk by scanning `team.json` + `teams/*.json` for a member/workstream with that session (unique → use it; multiple → ambiguous).
    4. **Discovery fallback** — only when no current identity is provable. A single configured profile shows its workstream as context (`amq:<workstream>`, no `@handle`); multiple profiles with no proof → `amq:?` (degraded marker). Never silently picks the first profile.
    - Base root = `$AM_BASE_ROOT` else the nearest `.agent-mail` walking up from `cwd`; the squad config dir is the nearest `.amq-squad`. The common live-pane path costs ~1 `jq` (reads one `launch.json`) and **no** `amq` subprocess; `amq env` only runs in the tier-3 fallback.

Key alignment rules:
- **Regular** line 2: `%2d` for 5h/7d/Fable
- **Heavy** line 2: `%2d` for 5h, `%3d` for 7d/Fable, `%4s` for cost

Env vars: `CLAUDE_PULSE_DENSITY` (minimal/regular/heavy/taboola), `CLAUDE_PULSE_HIDE_COST` (set to hide `💰` in heavy/taboola mode — recommended for Max/Pro users), `CLAUDE_PULSE_HIDE_DIFF` (set to hide `📝` git diff stats), `CLAUDE_PULSE_DEBUG_RATE_LIMITS=1` (one-shot privacy-safe dump of received rate-limit key names — see the Statusline JSON schema section)

### Git diff stats (v3.1.0)

Shows uncommitted changes (staged + unstaged) via `LC_ALL=C git diff HEAD --shortstat`. Color-coded: cyan for file count, green for insertions, red for deletions. Hidden when working tree is clean or `CLAUDE_PULSE_HIDE_DIFF` is set. Works in detached HEAD (gated on `git rev-parse --is-inside-work-tree`, not branch detection). Parsing uses bash `=~` regex (no sed subprocesses). In heavy mode, appears on line 2 with column alignment between model and alert sections.

### Model detection

- **Generic-first parsing (no per-model maintenance)**: modern IDs follow `claude-<family>-<major>-<minor>` and are parsed by one regex (`^claude-(opus|sonnet|haiku)-([0-9]+)-([0-9]+)`), so new releases (Opus 4.8, a future Sonnet 5.0, …) are recognized with **zero code changes**. A ≤2-digit minor guard (bash) / `(?![0-9])` lookahead (PowerShell) rejects 8-digit release dates like `claude-opus-4-20250512` so they don't read as "Opus 4.20250512".
- **Legacy table** handles only irregular IDs the parser can't: version-first names (`claude-3-5-sonnet`, `claude-4-5-haiku`), no-minor base-4 models (`claude-opus-4*` → "Opus 4.5", `claude-sonnet-4*` → "Sonnet 4.5"), and `claude-opus-3`/`claude-3-opus` → "Opus 3", `claude-3-7-sonnet` → "Sonnet 3.7".
- **Unknown IDs** fall back to Claude Code's own `model.display_name` from the statusline JSON (it already computes a friendly name), and only then to the literal "Claude".
- Recognized today: Opus 4.8, Opus 4.7, Opus 4.6, Opus 4.5, Sonnet 4.6, Sonnet 4.5, Sonnet 3.7, Sonnet 3.5, Haiku 4.5, Haiku 3.5, Opus 3 — plus any future modern-scheme release automatically.
- **Effort/thinking level — now exposed** (Claude Code added it after 2.1.114; confirmed present in 2.1.181): `.effort.level` (`low|medium|high|xhigh|max`; `xhigh` covers ultracode; absent when the model doesn't support the param) and `.thinking.enabled`. Parsed into the `effort` variable and rendered by **taboola** mode. The older claim in https://github.com/anthropics/claude-code/issues/31987 is obsolete.

### Conversation name feature

- **Primary: native `session_name`**: Claude Code exposes `session_name` in the statusline JSON input (set by `/rename` or auto-generated). Used directly when present — zero API calls, no caching needed.
- **Fallback (older Claude Code)**: When `session_name` is absent, falls back to: (1) session summary from `sessions-index.json`, (2) first 3 assistant messages from the transcript JSONL
- **AI API providers** (fallback only): Tries Anthropic → OpenAI → Gemini in order; falls back to first 3 words if no API available
- **Caching** (fallback only): Names cached in `~/.cache/claude-pulse/{session_id}.name` with MD5 hash of source text for invalidation
- **Key learning**: `sessions-index.json` only gets populated after a session ends or user runs `/rename` — for active sessions, the transcript fallback is essential
- **Transcript structure**: User-typed prompts are NOT stored as plain text in `type: "user"` entries (those are mostly tool results). The `type: "assistant"` entries with `content[].type == "text"` contain the best topic signals
- API call logic is extracted into reusable functions (`generate_name_via_api` in bash, `Get-ConversationName` in PowerShell) to avoid duplication

### Dynamic tab title (v3.0.0)

- Sets terminal tab title to conversation name via OSC escape sequence (`\033]0;...\007`)
- Only fires when Claude Code doesn't provide its own `session_name` (avoids overwriting `/rename`)
- Sanitizes control characters to prevent terminal escape injection
- Deduped via `~/.cache/claude-pulse/.last_tab_title` — only writes when name changes
- Uses delayed background write (300ms) to fire after Claude Code's own title-setting
- Works across all modern terminals: Warp, iTerm2, WezTerm, Terminal.app, Kitty, Alacritty
- Configurable: `CLAUDE_PULSE_TAB_TITLE=off` to disable (on by default)

### Red Alert feature

- **Two-script architecture**: `red-alert-daemon.sh` polls the Pikud HaOref API in the background, writes state to `/tmp/red_alert_state.json`. `claude-pulse` reads this file (no network I/O in statusline).
- **Auto-start**: Daemon launches automatically when `RED_ALERT_CITIES` or `RED_ALERT_MODE` is set. PID tracked at `/tmp/red_alert_daemon.pid`.
- **City mapping**: English→Hebrew mapping uses a `case` statement (not `declare -A`) for bash 3.2 compatibility on macOS.
- **Alert persistence**: Active alerts shown for 60s, pre-alerts for 20min, all-clear for 15s after last detection.
- **Mock mode**: `RED_ALERT_MODE=mock` cycles through fake alerts for testing without API calls.
- **Testable paths**: `RED_ALERT_STATE_FILE` and `RED_ALERT_PID_FILE` env vars override defaults for isolated testing. Similarly, `CLAUDE_PULSE_CACHE_DIR` overrides `~/.cache/claude-pulse` (name/PR caches, update badges, diagnostics) — the test suite sandboxes it in `helpers.sh setup()` so runs are hermetic against the developer's real cache.

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

### OTA update system (v3.0.0)

- **`update.sh`**: Singleton-locked updater triggered by SessionStart hook. Checks GitHub releases (gh CLI for private repos, curl fallback), downloads tarball, verifies SHA256 checksum (fail-closed), validates scripts (syntax + shebang), applies atomically with backup/rollback.
- **`release.sh`**: Builds release tarball, computes SHA256, uploads both as GitHub release assets. Validates version consistency, clean tree, no existing tag.
- **Statusline badges**: `🔄 Updated to vX.Y.Z` (auto-applied) or `🔄 vX.Y.Z available` (notify mode). Read-only file checks, no network I/O.
- **Security**: Domain pinning (github.com only), fail-closed checksums, `umask 077`, crash recovery via `apply_in_progress` marker, stale lock recovery (10 min TTL).
- **Config**: `CLAUDE_PULSE_AUTO_UPDATE` — `auto` (default) or `notify`. `CLAUDE_PULSE_TAB_TITLE` — `on` (default) or `off`.

### Release process

Use `/release` skill or `./release.sh` directly. The skill enforces the full checklist.

**Version bump files** (ALL must match):
1. `claude-pulse` line 2 — `# claude-pulse vX.Y.Z:`
2. `claude-pulse.ps1` line 1 — `# claude-pulse.ps1 vX.Y.Z:`
3. `red-alert-daemon.sh` line 2 — `# red-alert-daemon.sh vX.Y.Z:`
4. `update.sh` line 2 — `# claude-pulse update.sh vX.Y.Z:`

**Documentation updates**:
5. `README.md` — version references + release highlights
6. `RELEASE.md` — add new release entry at the top

**Publish**: `./release.sh` builds tarball + checksums, uploads to GitHub. OTA delivers to users automatically.

## Dependencies

- **macOS/Linux**: bash, jq, curl (for AI API calls)
- **Windows**: PowerShell (built-in)

## Statusline JSON schema

Claude Code provides these fields to the statusline command via stdin:

```
session_id, transcript_path, cwd, model.id, model.display_name,
workspace, version, cost, context_window (total_input_tokens,
total_output_tokens, context_window_size, used_percentage,
remaining_percentage), rate_limits (five_hour/seven_day .used_percentage/.resets_at — nothing else as of 2.1.207 and 2.1.215),
effort.level, thinking.enabled
```

**Not available**: conversation name — still not exposed by Claude Code in the statusline JSON (native `session_name` from `/rename` is, however). Effort/thinking level became available after 2.1.114.

**Fable weekly quota — NOT exposed to statuslines (verified against the 2.1.207 and 2.1.215 binaries)**: `/usage` shows "Current week (Fable)", but that row comes from a separate OAuth fetch (`GET /api/oauth/usage`) rendered only inside the dialog (and mirrored to the SDK-only `get_usage` control request as `rate_limits.model_scoped`). The subtlety (traced in 2.1.215): Claude Code's header parser (`yhu`) *does* read **four** unified buckets — `five_hour`, `seven_day`, `seven_day_overage_included` ("Fable 5 limit"), `overage` — from `anthropic-ratelimit-unified-*` response headers into its in-memory cache (`zxt`), which is the statusline's own data source. But the statusline **serializer** then spreads only `five_hour` and `seven_day` into the payload, dropping the Fable/overage buckets. So the gate is the serializer, not data availability — and it has no model conditional, so switching to the Fable model does **not** surface it. There is no supported, credential-free local source: the OAuth endpoint needs Claude Code's stored credentials, and nothing rate-limit-related is persisted to disk (verified — the state dirs hold no usage data). Nor can it be **derived** from `seven_day`: per [support](https://support.claude.com/en/articles/15424964-claude-fable-5-on-your-plan), on Max/premium Fable *shares* the weekly pool (capped at 50% of it) so its consumption is a non-separable subset of `seven_day`, and on Pro/standard it's a separate usage-credit (`overage`) bucket entirely — either way the numerator isn't in the payload. claude-pulse therefore hides the Fable segment and keeps the payload-based detection (semantic keys → Fable-scoped metadata → `seven_day_overage_included`) so it lights up automatically if a future Claude Code adds the one-line serializer spread ([anthropics/claude-code#27915](https://github.com/anthropics/claude-code/issues/27915)). `CLAUDE_PULSE_DEBUG_RATE_LIMITS=1` writes a one-shot privacy-safe diagnostic (capture time, Claude Code version, model id, rate-limit key names only) to `~/.cache/claude-pulse/rate-limits-debug.json` (path override for tests: `CLAUDE_PULSE_DEBUG_RATE_LIMITS_FILE`); delete the file to re-capture.
