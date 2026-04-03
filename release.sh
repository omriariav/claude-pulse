#!/bin/bash
# release.sh: Build and publish a claude-pulse release with SHA256 checksums
# Usage: ./release.sh [version]
# If version is omitted, reads from claude-pulse line 2

set -euo pipefail

REPO="omriariav/claude-pulse"
RELEASE_FILES=(claude-pulse red-alert-daemon.sh update.sh install.sh)
RELEASE_DIRS=(static)
RELEASE_COMMANDS=(setup-statusline update-pulse uninstall-statusline uninstall-red-alert)

# Determine version
if [[ -n "${1:-}" ]]; then
    VERSION="$1"
else
    VERSION=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' claude-pulse)
fi

if [[ -z "$VERSION" ]]; then
    echo "Error: Could not determine version"
    exit 1
fi

TAG="v${VERSION}"
TARBALL_NAME="claude-pulse-${TAG}.tar.gz"

echo "=== Building release ${TAG} ==="

# Verify all required files exist
for f in "${RELEASE_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Missing required file: $f"
        exit 1
    fi
done

# Verify version consistency across ALL versioned files
pulse_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' claude-pulse)
ps1_ver=$(sed -n '1s/.*v\([0-9.]*\).*/\1/p' claude-pulse.ps1 2>/dev/null || echo "MISSING")
daemon_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' red-alert-daemon.sh)
update_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' update.sh)

echo "  claude-pulse:       v${pulse_ver}"
echo "  claude-pulse.ps1:   v${ps1_ver}"
echo "  red-alert-daemon:   v${daemon_ver}"
echo "  update.sh:          v${update_ver}"

if [[ "$pulse_ver" != "$VERSION" ]] || [[ "$daemon_ver" != "$VERSION" ]] || [[ "$update_ver" != "$VERSION" ]]; then
    echo "Error: Version mismatch — all files must be v${VERSION}"
    exit 1
fi
if [[ "$ps1_ver" != "$VERSION" ]]; then
    echo "Warning: claude-pulse.ps1 is v${ps1_ver} (expected v${VERSION})"
    read -rp "Continue anyway? [y/N] " ps1_confirm
    [[ "$ps1_confirm" == "y" || "$ps1_confirm" == "Y" ]] || exit 0
fi

# Check that tag doesn't already exist
if git tag -l "$TAG" | grep -q "$TAG"; then
    echo "Error: Tag ${TAG} already exists locally"
    exit 1
fi
if gh release view "$TAG" --repo "$REPO" &>/dev/null; then
    echo "Error: Release ${TAG} already exists on GitHub"
    exit 1
fi

# Safety checks: clean tree
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "Error: Working tree is dirty. Commit or stash changes before releasing."
    exit 1
fi

current_branch=$(git branch --show-current 2>/dev/null)
if [[ "$current_branch" != "main" ]]; then
    echo "Warning: Releasing from branch '${current_branch}' (not main)"
    read -rp "Continue? [y/N] " branch_confirm
    [[ "$branch_confirm" == "y" || "$branch_confirm" == "Y" ]] || exit 0
fi

# Build tarball
BUILD_DIR=$(mktemp -d)
CONTENT_DIR="${BUILD_DIR}/claude-pulse-${TAG}"
mkdir -p "$CONTENT_DIR"

for f in "${RELEASE_FILES[@]}"; do
    cp "$f" "$CONTENT_DIR/"
done
for d in "${RELEASE_DIRS[@]}"; do
    [[ -d "$d" ]] && cp -r "$d" "$CONTENT_DIR/"
done
mkdir -p "$CONTENT_DIR/commands"
for cmd in "${RELEASE_COMMANDS[@]}"; do
    cp ".claude/commands/${cmd}.md" "$CONTENT_DIR/commands/"
done

(cd "$BUILD_DIR" && tar czf "$TARBALL_NAME" "claude-pulse-${TAG}/")
mv "${BUILD_DIR}/${TARBALL_NAME}" "./${TARBALL_NAME}"

# Generate SHA256 checksum
CHECKSUM_FILE="checksums.sha256"
shasum -a 256 "$TARBALL_NAME" > "$CHECKSUM_FILE"
echo ""
echo "Checksum:"
cat "$CHECKSUM_FILE"

# Clean up build dir
rm -rf "$BUILD_DIR"

# Confirm before publishing
echo ""
echo "Files ready:"
echo "  ${TARBALL_NAME} ($(du -h "$TARBALL_NAME" | cut -f1))"
echo "  ${CHECKSUM_FILE}"
echo ""
read -rp "Publish ${TAG} to ${REPO}? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    rm -f "$TARBALL_NAME" "$CHECKSUM_FILE"
    exit 0
fi

# Create GitHub release with assets
echo ""
echo "Creating release ${TAG}..."
if ! gh release create "$TAG" \
    --repo "$REPO" \
    --title "${TAG}" \
    --generate-notes \
    "$TARBALL_NAME" \
    "$CHECKSUM_FILE"; then
    echo ""
    echo "ERROR: Release creation failed."
    echo "To clean up a partial release/tag:"
    echo "  gh release delete ${TAG} --repo ${REPO} --yes 2>/dev/null"
    echo "  git tag -d ${TAG} 2>/dev/null"
    echo "  git push origin :refs/tags/${TAG} 2>/dev/null"
    echo "Local artifacts preserved: ${TARBALL_NAME}, ${CHECKSUM_FILE}"
    exit 1
fi

echo ""
echo "Release published: https://github.com/${REPO}/releases/tag/${TAG}"

# Verify checksum asset is attached (required for OTA)
if ! gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null | grep -q "checksums.sha256"; then
    echo "WARNING: checksums.sha256 not found in release assets — OTA will reject this release"
fi

# Clean up local artifacts
rm -f "$TARBALL_NAME" "$CHECKSUM_FILE"
