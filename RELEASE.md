# Release Notes

## v3.3.0 - Taboola density mode

**Released:** June 21, 2026

### Features

- **New opt-in `taboola` density** (`CLAUDE_PULSE_DENSITY=taboola`) — a slick, emoji-free single line modeled on a hand-rolled team statusline. Never auto-selected; opt-in only. Layout: `project │ branch [↑2] * │ amq:team │ Op4.8 high │ 38% │ 5h:23% 7d:41% │ $0.42 │ 🟢`
  - **Theme-adaptive colors** — uses standard 16-color ANSI (`\033[34m` etc.) instead of claude-pulse's truecolor RGB, so it follows the terminal's own color scheme. Honors `NO_COLOR`.
  - **amq-squad team/session** — surfaces the active squad as `amq:team/session@handle`. Team comes from the nearest `.amq-squad/team.json` (`.workstream`, walking up from `cwd`); session from `amq env --session-name` (or `$AM_ROOT` basename); handle from `$AM_ME`. Each part is independently optional.
  - **Reasoning effort** — now that Claude Code exposes `.effort.level` (`low|medium|high|xhigh|max`) in the statusline JSON, it's shown as a magenta, abbreviated suffix on the model (`low→L medium→M high→H xhigh→XH max→MAX`; omitted when the model doesn't support the param).
  - **Remaining context %** (health-colored), **5h/7d rate limits**, and **API cost** (cents precision, respects `CLAUDE_PULSE_HIDE_COST`) on the same line. Last-folder-only directory and short model label (`Op4.8`).
  - **PowerShell parity** — the same mode is implemented in `claude-pulse.ps1`.

### Bug Fixes

- **Statusline rendered nothing despite producing output** — the script ended on a `[[ ... ]]` test that could evaluate false, so it exited non-zero; recent Claude Code treats a non-zero statusline exit as a failure and shows an empty line. The script now always `exit 0`.

### Tests

- New `tests/test_taboola.sh` suite (21 assertions): basename dir, short model label, effort, remaining %, 5h/7d, cost show/hide/\$0, 16-color (not truecolor) palette, `NO_COLOR` stripping, amq team detection, and exit-0.

## v3.2.0 - Generic model detection

**Released:** June 3, 2026

### Features

- **Future model releases need no code change** — the modern ID scheme (`claude-<family>-<major>-<minor>`) is now parsed generically by a single regex, so a new release like **Opus 4.8** (and any future Sonnet/Haiku/Opus version) is recognized automatically. Both the full name (`Opus 4.8`) and the minimal-density short form (`Op4.8`) are derived from the ID. This replaces the per-model `case`/`switch` block that required a new branch — and a new release — for every model (cf. v3.1.3 for 4.7, v2.5.1 for Sonnet 4.6).
- **`display_name` fallback for unknown IDs** — anything the parser doesn't recognize (e.g. an entirely new model *family*) now falls back to Claude Code's own `model.display_name` from the statusline JSON before defaulting to the literal "Claude", so it shows a real name instead of a generic one.

### Bug Fixes

- **Opus 4.8 misidentified as "Opus 4.5"** — `claude-opus-4-8` fell through to the generic `claude-opus-4*` arm. Fixed by the generic parser above. A ≤2-digit minor guard (bash) / `(?![0-9])` lookahead (PowerShell) ensures 8-digit release dates like `claude-opus-4-20250512` aren't misread as a minor version.

### Internal

- **CI** — added a GitHub Actions workflow that runs the full test suite on `macos-latest` (matching the script's real bash 3.2 + BSD-tooling target) for every PR and push to `main`.

### Tests

- New regression coverage: `claude-opus-4-8[1m]` (incl. the `[1m]` context suffix), generically-parsed `claude-sonnet-5-0`, and the `display_name` fallback path. Full suite now 210 assertions.

## v3.1.4 - Red Alert: cat=14 resolution routing

**Released:** May 20, 2026

### Bug Fixes

- **`⚠️ Pre-alert — be prepared` shown for "concern removed" updates** — Pikud HaOref's API uses `cat=14` as a junk drawer for both forward-looking pre-alerts (*"in the coming minutes expect alerts"*) and backward-looking resolutions (*"הוסר החשש לחדירת מחבלים"* — "concern of terrorist infiltration removed"). The daemon now detects resolution titles and skips the state write entirely (matching the existing `cat=10` "הסתיים" precedent), so the statusline never renders "be prepared" for a threat that was actually resolved.
- **`cat=10` ended-event detection broadened** — extended the existing `הסתיים`-only check to share the same helper with `cat=14`, picking up gender/plural variants (`הוסרה`/`הוסרו`/`הסתיימה`/`הסתיימו`) and additional resolution verbs (`בוטל`/`בוטלה`/`בוטלו`, `נשלל`/`נשללה`/`נשללו`, `אין חשש`).

### Tests

- 19 new assertions in `test_resolution_titles.sh` covering 13 resolution variants and 6 legitimate pre-alert / active-alert titles (including the empty-title edge case).

## v3.1.3 - Opus 4.7 & Haiku 4.5 Support

**Released:** April 18, 2026

### Bug Fixes

- **Opus 4.7 misidentified as "Opus 4.5"** — the generic `claude-opus-4*` case pattern was shadowing the newer model. Added a more specific `claude-opus-4-7*` case above it. Patterns are now documented as "most-specific first".
- **Haiku 4.5 not recognized** — previously fell through to the generic "Claude" fallback. Added `claude-haiku-4-5*` / `claude-4-5-haiku*` patterns.

### Not Included

- **Thinking/effort level display** — Claude Code 2.1.114 does not expose the current `/effort` level (`low`/`medium`/`high`/`xhigh`/`max`) in the statusline stdin JSON. Tracking upstream at [anthropics/claude-code#31987](https://github.com/anthropics/claude-code/issues/31987); will wire it up once the field lands.

### Tests

- 4 new entries in the model-detection matrix for `claude-opus-4-7*` and `claude-haiku-4-5*`
- Regression assertion that Opus 4.7 output never contains "Opus 4.5" or "Opus 4.6"

## v3.1.2 - Minimal Mode Polish

**Released:** April 5, 2026

### Improvements

- **Compact minimal indicators** — Red Alert daemon status shows emoji-only in minimal density (`🟢`/`🔕`/`🟡`) instead of full text, saving horizontal space on narrow terminals

### Tests

- 9 new tests for minimal mode alert indicators covering all daemon states (running, not running, version mismatch) with regular mode comparison
- Version mismatch test made hermetic with fake HOME for CI portability

## v3.1.1 - Regression Fixes

**Released:** April 3, 2026

### Bug Fixes

- **Setup KeepAlive fix** — `/setup-statusline` no longer sets `KeepAlive=true` in the Red Alert daemon plist (daemon self-heals via backoff; KeepAlive caused restart loops)
- **Heavy mode alignment** — removed column padding that created a large gap after model name on clean working trees; fixed 2-space indent on fallback line 2
- **Diff stats on line 1** — heavy mode now shows `📝` diff stats on line 1 (consistent with regular mode), instead of line 2
- **Setup portability** — `/setup-statusline` now works from any project directory (detects partial installs, only requires repo for first install)
- **Plist absolute paths** — setup skill emphasizes absolute `$HOME` paths in plist (launchd doesn't expand `~`)

### Improvements

- **User-level skills** — setup copies management skills (`/setup-statusline`, `/update-pulse`, `/uninstall-statusline`, `/uninstall-red-alert`) to `~/.claude/commands/` for global access
- **OTA skill updates** — release tarball now includes command files; OTA updates them alongside scripts
- **Uninstall cleanup** — `/uninstall-statusline` now removes `update.sh` and user-level skill files
- **install.sh tarball compat** — tries both repo and tarball paths when copying skills

### Tests

- Regression tests for diff stats placement (line 1 in heavy/regular) and gap detection
- OTA test verifies all 4 command files are copied during update

## v3.1.0 - Git Diff Stats

**Released:** March 31, 2026

### What's New

- **Git diff stats in statusline** — shows files changed, insertions (+green), and deletions (-red) with cyan file count. Density-aware: minimal (`3f +45 -12`), regular (`📝 3f +45 -12`), heavy (`📝 3 files +45 -12` on line 2 with column alignment)
- **`CLAUDE_PULSE_HIDE_DIFF` env var** — set to hide the diff stats segment
- **Minimal branch name** — increased from 10 to 18 chars for better readability
- **Heavy mode column alignment** — model section (line 1) and alert section (line 2) are padded so `·` separators stack vertically

### Bug Fixes

- **Missile sound cooldown** — increased from 40s to 60s to prevent repeated plays during multi-wave sirens

## v3.0.2 - API Failure Backoff

**Released:** March 29, 2026

### What's New

- **Exponential backoff for API failures** — daemon no longer dies after consecutive failures (e.g., lid close/sleep). Uses tiered backoff (2s, 10s, capped at 10s) and self-heals when network recovers. First valid response resets to normal polling.
- **OTA test uses dynamic version** — no longer hardcoded, works across version bumps

## v3.0.1 - OTA Updates, Security Hardening, Tab Titles

**Released:** March 28, 2026

### What's New

- **OTA update system** — automatic updates via GitHub releases with SHA256 checksum verification (fail-closed), domain pinning, atomic swap with rollback, and crash recovery
- **Dynamic terminal tab titles** — sets tab to conversation name via OSC escape (works across Warp, iTerm2, WezTerm, Terminal.app, Kitty, Alacritty)
- **Read-only statusline** — removed all `launchctl`/`kill` calls from the render loop; uses restart markers instead
- **Daemon version tracking** — detects version mismatch, shows "update pending" badge
- **API failure backoff** — Red Alert daemon stops polling after 30 consecutive failures (non-Israeli IP detection)
- **`/release` skill** — guided release process enforcing version bump, docs, Codex review, and `release.sh` publish
- **`/update-pulse` command** — manual update trigger for notify-mode users
- **Security**: SSH commit signing required on main, branch protection, secret scanning, `umask 077`

### Bug Fixes

- Fixed empty line 2 on fresh conversations ($0 cost, missing rates)
- Fixed percent alignment in heavy mode (`%2d` padding)
- Fixed `local` outside function scope in heavy mode fallback
- Fixed SessionStart hooks using wrong schema format

## v3.0.0 - Adaptive Density Statusline

**Released:** March 27, 2026

### What's New

- **Three density tiers** — auto-detected from terminal width, overridable with `CLAUDE_PULSE_DENSITY`:
  - **Minimal** (< 100 cols): Single line, no bar, abbreviated model, `│` separators
  - **Regular** (100–159 cols): Two lines, 10-char bare bar, emoji dividers, smart truncation
  - **Heavy** (≥ 160 cols): Two lines, 20-char bracketed bar, ` · ` dot separators, full detail
- **ANSI RGB color palette** — richer colors using `$'...'` bash literals
- **Session cost display** — `💰 $18` in heavy mode (whole dollars). Hide with `CLAUDE_PULSE_HIDE_COST=1` for Max/Pro users.
- **`/setup-statusline` command** — unified interactive onboarding: density preview (Ctrl+O), cost toggle, Red Alert config
- **`/uninstall-statusline` command** — full teardown of scripts, daemon, and settings
- **Aligned line 2** — rate limits and alerts stack visually under line 1 segments

### What's Fixed

- **Line 1 overflow** — long branch names + full CWD paths no longer wrap and bleed into Claude Code UI
- **City accumulation on re-poll** — merged cities preserved when daemon re-polls same alert ID

### Upgrade from v2.x

```bash
cd claude-pulse
git pull
./install.sh
```

Auto-detection means v3.0 works immediately with no config. To customize density, cost display, or Red Alert, run `/setup-statusline` inside Claude Code.

### Breaking Changes

- Visual output format changed (3 tiers replace the single fixed layout)
- `/setup-red-alert` removed — use `/setup-statusline` instead
- Color codes changed from basic ANSI to RGB (tests updated)

---

## v2.5.2 - Pre-Alert Persistence + Hook Fix

**Released:** March 27, 2026

### What's Fixed

- **Pre-alert banner persists after main alert expires** — Pre-alert was dropped from state when the main alert transitioned to all-clear, event-ended, or empty, even if the pre-alert's own TTL hadn't expired. Now carried forward as long as its `display_until_unix` is still active, independent of the main alert's lifecycle.
- **SessionStart hook no longer kills the running daemon** — Removed `-k` from `launchctl kickstart` so opening a new Claude Code session no longer restarts the daemon. Alert state is preserved across sessions.

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

Update the SessionStart hook in `~/.claude/settings.json` — remove the `-k` flag from `kickstart`:
```bash
launchctl list | grep -q com.claude-pulse.red-alert || launchctl load ~/Library/LaunchAgents/com.claude-pulse.red-alert.plist; launchctl kickstart "gui/$(id -u)/com.claude-pulse.red-alert" >/dev/null 2>&1; true
```

---

## v2.5.1 - Fix Sonnet 4.6 Model Detection

**Released:** March 27, 2026

### Bug Fix

Sonnet 4.6 was incorrectly displayed as "Sonnet 4.5" in the statusline. The `claude-sonnet-4*` wildcard was too broad and matched all Sonnet 4.x models before version-specific patterns could be checked.

Added explicit `claude-sonnet-4-6*` and `claude-sonnet-4-5*` patterns (most specific first) in both the bash and PowerShell scripts, matching the same ordering already used for Opus models.

### Upgrade

```bash
cd claude-pulse
git pull
cp claude-pulse ~/.claude/statusline-command.sh
```

---

## v2.5.0 - Native Conversation Names

**Released:** March 26, 2026

### What's New

Claude Code now exposes `session_name` in the statusline JSON input. This is the conversation name set by `/rename` or auto-generated by Claude Code. claude-pulse uses this as the primary source for the `💬` conversation name segment, eliminating the need for AI API calls, transcript parsing, and caching when the field is present.

Falls back to the existing AI-generated approach (Anthropic → OpenAI → Gemini → first 3 words) for older Claude Code versions that don't provide `session_name`.

Added 13 new tests covering conversation name display, truncation, rate limit colors, and progress bar rendering. Total: 106 tests across 6 suites.

### Upgrade

```bash
cd claude-pulse
git pull
cp claude-pulse ~/.claude/statusline-command.sh
```

---

## v2.4.2 - Alert City Merging (Main + Pre-Alert)

**Released:** March 26, 2026

### What's Fixed

v2.4.1 only merged pre-alert cities. This release also merges main alert cities. When multiple missile waves hit different areas, all cities accumulate in the state file until their TTL expires. Discovered during a live alert where Tel Aviv disappeared from display when a subsequent wave hit the Sharon area.

Added 11 tests covering all merge paths: main alert merge, pre-alert merge, back-to-back pre-alerts, expiry boundary, same-ID dedup, and cross-category non-merge.

Also fixed the SessionStart hook: `launchctl load` errors when the service is already running via `RunAtLoad`. Now checks if loaded first. The `/setup-red-alert` command now configures this hook automatically.

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

---

## v2.4.1 - Pre-Alert City Merge

**Released:** March 26, 2026

### What's Fixed

Pre-alerts for different areas no longer overwrite each other. When a new pre-alert arrives while an existing one's TTL is still active, cities from both are merged (union). This prevents losing visual alerts for your area when the API sends a new pre-alert wave for a different region.

**Example:** Pre-alert for Ramla at 17:02, then pre-alert for Sharon area at 17:05. Previously, Ramla disappeared. Now both areas' cities are combined until the TTL expires.

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

---

## v2.4.0 - Alert Logic Refactor

**Released:** March 26, 2026

### What's Changed

- **Extracted city filter into reusable function** -- single source of truth for 30-city English/Hebrew mapping, called for both main alert and pre_alert independently. Fixes #16 (pre-alert not displayed when main alert filtered out).
- **Extracted alert evaluation function** -- determines active/recent/expired state for any alert. Eliminates fragile variable-swapping pattern.
- **Explicit winner matrix** -- priority selection is now a clear 6-step matrix instead of nested conditionals: main active > pre active > global category > main recent > daemon status.
- **Per-sound-class cooldown** -- missiles (go.m4a) have 40s cooldown, pre-alerts (early.m4a) have 120s cooldown, tracked independently. Fixes #13 (pre-alerts playing 3x in 45s).
- **Consolidated jq calls** -- 18 jq calls in alert section reduced to 4, 6 initial input calls reduced to 1. Uses Unit Separator delimiter instead of eval.
- **ANSI color variables** -- all escape codes defined once at top of file, replacing inline magic strings.
- **Test coverage** -- 79 tests across 5 suites (up from 59 across 3).

### Closed Issues

- #13: Per-category sound cooldown (per-sound-class cooldown)
- #14: Display lag (closed as known CC limitation, sound works correctly)
- #16: Pre-alert fallback when main alert filtered out (structurally eliminated)

### Upgrade

```bash
cd claude-pulse
git pull
cp claude-pulse ~/.claude/statusline-command.sh
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

---

## v2.3.2 - Sound Cooldown Fix

**Released:** March 26, 2026

### What's Changed

- Sound cooldown increased from 20s to 40s, reducing pre-alert sound repetition
- During a real pre-alert wave, `early.m4a` was playing 3 times in 45 seconds due to API sending new alert IDs
- Issue #13 remains open for a proper per-category cooldown solution

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

---

## v2.3.0 - Two-Tier Alert Display + Cat 10 Pre-Alert

**Released:** March 26, 2026

### What's New

- **Two-tier alert display** — Daemon writes `first_seen_unix` and `display_until_unix` to state. Red banner shows for `max(last_seen + 60, first_seen + 180)`, guaranteeing at least 3 minutes of visibility regardless of statusline refresh rate. After that, a subtle "Recent" indicator shows for up to 5 minutes.
- **Cat 10 title-based routing** — Cat 10 "האירוע הסתיים" (event ended) is still skipped. But cat 10 "בדקות הקרובות צפויות להתקבל התרעות" (alerts expected in your area) is now treated as pre-alert with sound.

### Why

A real missile alert hit Ramla at 08:23 — sound played correctly but the red banner never showed because the statusline refreshed after the 60s window expired. This was a safety gap: you heard the siren but had no visual confirmation of which cities were affected.

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
cp claude-pulse ~/.claude/statusline-command.sh
```

---

## v2.2.2 - Fix Daemon Dying During Idle Sessions

**Released:** March 26, 2026

### What's Fixed

The daemon was dying during idle Claude Code sessions. Root cause: `pgrep` confirmed CC was alive but the heartbeat check killed the daemon independently (statusline doesn't refresh during long idle periods).

Fix: if `pgrep` finds Claude Code, skip the heartbeat check entirely. Heartbeat is now fallback-only for when `pgrep` is unavailable.

### Impact

Previously, an idle CC session (e.g., left terminal open overnight) would lose the daemon after ~5 minutes. Real alerts during that window were missed — confirmed by a missed Tel Aviv alert wave at 01:29 on March 26.

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

---

## v2.2.1 - pgrep Fast Shutdown + Safe pgrep Fallback

**Released:** March 25, 2026

### What's New

- **pgrep fast-path shutdown** — Daemon checks if Claude Code process (`pgrep -x "claude"`) exists every poll cycle. After 3 consecutive misses (~6s), exits immediately instead of waiting for 300s heartbeat timeout.
- **Safe pgrep check** — Only uses pgrep when available (`command -v pgrep`). Falls through to heartbeat if pgrep is absent or broken.
- **Heartbeat timeout 300s** — Increased from 120s. Survives long idle periods without unnecessary restart churn.

### Shutdown Behavior

| Signal | Time to exit | How |
|--------|-------------|-----|
| Claude Code closes | ~6 seconds | pgrep misses 3x |
| pgrep unavailable | ~5 minutes | Heartbeat stale |
| Laptop sleep/wake | Survives | Heartbeat refreshed on wake |

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

---

## v2.2.0 - Daemon Stability + Category Fixes from Real Alerts

**Released:** March 25, 2026

### What's New

- **Cat 6 = UAV** - Real API data confirmed cat 6 is `חדירת כלי טיס עוין` (hostile aircraft/drone infiltration), not hazmat. Updated label to `✈️ UAV` and added to sound triggers.
- **Cat 10 = event ended** - Confirmed as `האירוע הסתיים`. Now logged only, no display or sound.
- **Daemon singleton lock** - Atomic `mkdir` lock held for daemon lifetime. PID stored inside lock dir. Contenders wait 1s for init race before declaring stale.
- **Safe PID cleanup** - Cleanup only removes PID/lock if they belong to the exiting process.
- **Heartbeat timeout 120s** - Daemon no longer dies during idle Claude Code periods.
- **Statusline kickstart only at zero** - Auto-restart only fires when truly zero daemons running.
- **Debug mode** - `RED_ALERT_DEBUG=1` shows `(N)` daemon count in statusline and logs lock contention events.
- **Alert title logging** - Hebrew title from API now logged for category identification.

### Category Map (confirmed from real alerts)

| Cat | Title | Label | Sound |
|-----|-------|-------|-------|
| 1 | ירי רקטות וטילים | MISSILES | go.m4a |
| 2 | (hostile aircraft) | AIRCRAFT | go.m4a |
| 6 | חדירת כלי טיס עוין | UAV | go.m4a |
| 10 | האירוע הסתיים | (skipped) | none |
| 14 | (pre-alert) | PRE-ALERT | early.m4a |

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
cp claude-pulse ~/.claude/statusline-command.sh
```

---

## v2.1.1 - Sound Only for Actionable Alerts

**Released:** March 25, 2026

### What's Changed

- Sound now only plays for **cat 1 (missiles)** and **cat 2 (hostile aircraft)** → `go.m4a`
- **Cat 14 (pre-alert)** continues to play `early.m4a`
- All other categories (earthquake, hazmat, drills, unknown cat 10, etc.) still display visually but are silent
- No changes to statusline display — all categories still render

### Why

Category 10 (undocumented) appeared during today's alerts with the same cities as missile alerts, triggering unnecessary sounds. Only cat 1 and 2 require immediate action (go to shelter).

### Upgrade

```bash
cd claude-pulse
git pull
cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
```

---

## v2.1.0 - Rate Limits + Alert Bug Fixes

**Released:** March 25, 2026

### What's New

- **Rate limit display**: Shows `⚡ 5h: 23% · 7d: 5%` on 2nd line, color-coded like the context bar (green/yellow/red). Pro/Max subscribers only — API key users see nothing (graceful degradation).
- **Sound city filtering**: Alert sounds now respect `RED_ALERT_CITIES` filter. Previously, sounds played for ALL alerts regardless of city config.
- **Daemon auto-restart**: Statusline detects dead daemon and restarts via `launchctl kickstart`.
- **No duplicate daemons**: `pgrep` guard prevents spawning multiple daemon processes from concurrent statusline refreshes.
- **Empty filter fix**: Trailing commas in `RED_ALERT_CITIES` no longer cause match-all behavior.
- **Hebrew fallback in daemon**: Daemon's city matching now has the same English→Hebrew map as the statusline, preventing sound/display disagreement.

### Display Format

```
🧠 [████░░░░░░░░░░░░░░░░] 28% · 🤖 Opus 4.6 (200k) · 💬 Topic · 🌿 main 📁 ~/Code/project
⚡ 5h: 23% · 7d: 5% · 🟢 Alerts daemon ON
```

With active alert:
```
🧠 [████░░░░░░░░░░░░░░░░] 28% · 🤖 Opus 4.6 (200k) · 💬 Topic · 🌿 main 📁 ~/Code/project
⚡5h:39% 7d:8% · 🚀 MISSILES · Tel Aviv - City Center
```

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
```

---

## v2.0.0 - Red Alert (Pikud HaOref)

**Released:** March 25, 2026

### What's New

- **Real-time alerts**: Pikud HaOref rocket alert notifications in the statusline
- **City & zone filtering**: Monitor specific cities or zones with fuzzy matching (English or Hebrew)
- **English city names**: 1492 locations translated via official oref.org.il districts
- **Alert sounds**: macOS m4a playback with per-class cooldown (40s missiles, 120s pre-alerts)
- **launchd integration**: Daemon managed by macOS LaunchAgent, single instance guaranteed
- **Heartbeat lifecycle**: Daemon self-terminates 30s after all Claude Code instances close
- **Interactive setup**: `/setup-red-alert` command with city/zone selection
- **Test suite**: 51 tests across 3 suites

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
/setup-red-alert
```

---

## v1.7.1 - Context Window Label

**Released:** March 11, 2026

### What's New

- **Context window size in status line**: Shows `(200k)` or `(1M)` next to the model name, making it easy to distinguish standard vs extended context sessions at a glance

### Display Format

Before (v1.7.0):
```
🧠 [██████░░░░░░░░░░░░░░] 32% · 🤖 Opus 4.6 · 💬 Topic Name · 🌿 feat/bar 📁 ~/Code/project
```

After (v1.7.1):
```
🧠 [██████░░░░░░░░░░░░░░] 32% · 🤖 Opus 4.6 (1M) · 💬 Topic Name · 🌿 feat/bar 📁 ~/Code/project
```

### Upgrade

```bash
cd claude-pulse
git pull
./install.sh
```

---

## v1.7.0 - Context Bar, Branch/PR, Cleaner Topic UX

**Released:** February 23, 2026

### What's New

- **Visual context bar**: 20-character progress bar shows context **consumed** — bar fills up as you use more context, color shifts from green to yellow to red
- **Git branch + PR number**: Shows current branch (e.g., `🌿 feat/bar`) and open PR number (e.g., `🌿 fix/auth (#42)`) with 10-minute caching to avoid slow API calls
- **Cleaner topic names**: Removed noisy quotes around conversation names, added 20-char truncation with `..` for long names
- **macOS-compatible timeout**: PR lookup uses portable background-process timeout instead of GNU `timeout`
- **Atomic cache writes**: All cache files written via temp+rename to prevent partial reads
- **Bash/PowerShell parity**: Consistent rounding at color thresholds across platforms

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
