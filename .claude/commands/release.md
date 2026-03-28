---
name: release
description: Release a new version of claude-pulse — version bump, docs, review, and publish
user_invocable: true
---

# Release claude-pulse

Guided release process. Claude runs each step, confirming with the user before publishing.

## Pre-flight checks

1. Confirm we're on `main` branch (or prompt to merge first)
2. Confirm all tests pass: `bash tests/run_tests.sh && bash tests/test_ota_update.sh`
3. Confirm working tree is clean

If any check fails, stop and help the user fix it before proceeding.

## Step 1: Determine version

Ask the user what version to release. Show the current version:
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
5. `release.sh` — no version in file (reads from claude-pulse)

After editing, verify consistency:
```bash
echo "claude-pulse: $(sed -n '2s/.*v\([0-9.]*\).*/\1/p' claude-pulse)"
echo "claude-pulse.ps1: $(sed -n '1s/.*v\([0-9.]*\).*/\1/p' claude-pulse.ps1)"
echo "red-alert-daemon: $(sed -n '2s/.*v\([0-9.]*\).*/\1/p' red-alert-daemon.sh)"
echo "update.sh: $(sed -n '2s/.*v\([0-9.]*\).*/\1/p' update.sh)"
```

All must show the same version.

## Step 3: Update documentation

### README.md
- Update version badge number
- Add "New in vX.Y.Z" section with feature highlights
- Move previous version's section to "Previous Updates"

### RELEASE.md
- Add new release entry at the TOP with date, version, and changelog

## Step 4: Codex review

Run a Codex review focused on the changes in this release. The review must be CLEAN (no blocking High/Critical findings) before proceeding.

If there are findings, fix them and re-review. Do NOT skip this step.

## Step 5: Commit and push

Create a single commit with all version bump + docs changes:
```
release: vX.Y.Z — [one-line summary of release]
```

Push to main (commit will be signed automatically).

## Step 6: Publish release

Run the release script:
```bash
./release.sh
```

This will:
- Verify clean tree and version consistency
- Build tarball with all release files
- Compute SHA256 checksum
- Upload both as GitHub release assets
- Create the GitHub release with auto-generated notes

## Step 7: Verify

1. Check the release page: `gh release view vX.Y.Z --repo omriariav/claude-pulse`
2. Verify OTA will pick it up: `cat ~/.cache/claude-pulse/last_update_check` (clear if needed)
3. Confirm local install is current: `sed -n '2p' ~/.claude/statusline-command.sh`

## Post-release

Tell the user the release is live and OTA will deliver it to all users on their next session start.
