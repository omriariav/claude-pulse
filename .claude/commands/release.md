---
name: release
description: Release a new version of claude-pulse — version bump, docs, review, and publish
user_invocable: true
---

# Release claude-pulse

Guided release process. Claude runs each step, confirming with the user before publishing.

## Pre-flight checks

Run ALL of these before proceeding. Stop on any failure.

1. Confirm we're on `main` branch with latest changes pulled:
   ```bash
   git branch --show-current && git pull --ff-only
   ```
   If NOT on main: the release PR must be merged first. Help the user merge, then pull.

2. Confirm working tree is clean: `git status --porcelain` must be empty

3. Confirm all tests pass:
   ```bash
   bash tests/run_tests.sh && bash tests/test_ota_update.sh
   ```

4. Confirm commit signing is working:
   ```bash
   git log -1 --format='%G?' | grep -q 'G' && echo "Signing OK" || echo "WARNING: signing not configured"
   ```

5. Check that the target version tag does NOT already exist:
   ```bash
   git tag -l "vX.Y.Z" && gh release view vX.Y.Z --repo omriariav/claude-pulse 2>&1
   ```
   If tag/release exists, abort and choose a different version.

If any check fails, stop and help the user fix it before proceeding.

## Step 1: Determine version

Show the current version:
```bash
sed -n '2s/.*v\([0-9.]*\).*/\1/p' claude-pulse
```

Use `AskUserQuestion` to confirm the new version number. Suggest based on changes:
- Patch (X.Y.Z+1): bug fixes only
- Minor (X.Y+1.0): new features, backward compatible
- Major (X+1.0.0): breaking changes

## Step 2: Version bump (ALL files)

Update version string in ALL of these files — missing any is a release blocker:

1. `claude-pulse` line 2 — `# claude-pulse vX.Y.Z:`
2. `claude-pulse.ps1` line 1 — `# claude-pulse.ps1 vX.Y.Z:`
3. `red-alert-daemon.sh` line 2 — `# red-alert-daemon.sh vX.Y.Z:`
4. `update.sh` line 2 — `# claude-pulse update.sh vX.Y.Z:`

After editing, verify consistency — ALL must match:
```bash
echo "claude-pulse:      $(sed -n '2s/.*v\([0-9.]*\).*/\1/p' claude-pulse)"
echo "claude-pulse.ps1:  $(sed -n '1s/.*v\([0-9.]*\).*/\1/p' claude-pulse.ps1)"
echo "red-alert-daemon:  $(sed -n '2s/.*v\([0-9.]*\).*/\1/p' red-alert-daemon.sh)"
echo "update.sh:         $(sed -n '2s/.*v\([0-9.]*\).*/\1/p' update.sh)"
```

NOTE: `release.sh` validates `claude-pulse`, `red-alert-daemon.sh`, and `update.sh` at publish time.
`claude-pulse.ps1` is NOT checked by release.sh — you must verify it manually here.

## Step 3: Update documentation

### README.md
- Read the current README first to understand its structure
- Update version references
- Add release highlights for this version

### RELEASE.md
- Add new release entry at the TOP with date, version, and changelog

## Step 4: Codex review

Run a Codex review of ALL changes since the last release (git diff of the bumped files + docs).
The review must have NO blocking High/Critical findings before proceeding.

If there are findings: fix them, re-run tests, and re-review. Do NOT skip this step.

## Step 5: Commit and push

Create a single signed commit with all version bump + docs changes:
```
release: vX.Y.Z — [one-line summary of release]
```

Push to main. Verify the commit is signed:
```bash
git log -1 --show-signature
```

If push is rejected by branch protection, create a release PR instead and merge it.

## Step 6: Publish release

Run the release script:
```bash
./release.sh
```

This will:
- Verify clean tree and version consistency
- Build tarball with all release files
- Compute SHA256 checksum
- Prompt for confirmation before publishing
- Upload tarball + checksums.sha256 as GitHub release assets
- Create the GitHub release with auto-generated notes

**If release.sh fails mid-publish:**
1. Check if a partial release/tag was created: `gh release view vX.Y.Z 2>&1`
2. If partial: delete and retry: `gh release delete vX.Y.Z --yes && git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z`
3. Clean up local artifacts: `rm -f claude-pulse-*.tar.gz checksums.sha256`
4. Re-run `./release.sh`

## Step 7: Verify

1. Confirm release page and assets:
   ```bash
   gh release view vX.Y.Z --repo omriariav/claude-pulse
   ```

2. Verify checksums.sha256 is attached (required for OTA):
   ```bash
   gh release view vX.Y.Z --json assets --jq '.assets[].name' | grep checksums
   ```

3. Install locally and verify:
   ```bash
   cp claude-pulse ~/.claude/statusline-command.sh
   cp red-alert-daemon.sh ~/.claude/red-alert-daemon.sh
   cp update.sh ~/.claude/update.sh
   sed -n '2p' ~/.claude/statusline-command.sh
   ```

4. Clear OTA cache so next session picks up the release:
   ```bash
   rm -f ~/.cache/claude-pulse/last_update_check
   ```

## Post-release

Tell the user:
- Release is live at the GitHub releases page
- OTA will deliver it to all users on their next session start
- Local install is updated
