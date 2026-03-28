#!/bin/bash
# claude-pulse update.sh v3.0.0: OTA update manager
# Checks GitHub releases, downloads, validates, and applies updates atomically
# Triggered by SessionStart hook — runs in background, singleton-locked

set -euo pipefail

REPO="omriariav/claude-pulse"
CLAUDE_DIR="$HOME/.claude"
CACHE_DIR="$HOME/.cache/claude-pulse"
STATE_DIR="$HOME/.local/state/claude-pulse"
STAGING_DIR="${CACHE_DIR}/staging"
LOG_FILE="${STATE_DIR}/update.log"

# Files managed by OTA
OTA_FILES=(statusline-command.sh red-alert-daemon.sh update.sh)
OTA_STATIC_GLOB="static/*.m4a"

# Update mode: auto (default) or notify
UPDATE_MODE="${CLAUDE_PULSE_AUTO_UPDATE:-auto}"

mkdir -p "$CACHE_DIR" "$STATE_DIR" 2>/dev/null

log() { printf '%s [update] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE" 2>/dev/null; }

# Singleton lock — only one update.sh runs at a time
LOCK_DIR="${CACHE_DIR}/update.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# Rate limit: skip if last check < 1 hour ago
LAST_CHECK_FILE="${CACHE_DIR}/last_update_check"
if [[ -f "$LAST_CHECK_FILE" ]]; then
    last_check=$(cat "$LAST_CHECK_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( now - last_check < 3600 )); then
        log "Rate limited (last check $(( now - last_check ))s ago)"
        exit 0
    fi
fi

# Extract current installed version from line 2 of statusline script
get_installed_version() {
    sed -n '2s/.*v\([0-9.]*\).*/\1/p' "${CLAUDE_DIR}/statusline-command.sh" 2>/dev/null
}

# Compare semver: returns 0 if $1 > $2
semver_gt() {
    local IFS=.
    local i a=($1) b=($2)
    for ((i=0; i<${#a[@]}; i++)); do
        local av=${a[i]:-0} bv=${b[i]:-0}
        if (( av > bv )); then return 0; fi
        if (( av < bv )); then return 1; fi
    done
    return 1
}

# Check for new release on GitHub
check_update() {
    local current_ver="$1"
    log "Checking for updates (current: v${current_ver})"

    # Fetch latest release — use gh CLI (handles private repos) with curl fallback
    local api_response=""
    if command -v gh &>/dev/null; then
        api_response=$(gh api "repos/${REPO}/releases/latest" 2>/dev/null) || true
    fi
    if [[ -z "$api_response" ]]; then
        api_response=$(curl --proto '=https' --tlsv1.2 --fail --silent --max-time 10 \
            "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null) || {
            log "Failed to fetch release info"
            return 1
        }
    fi

    # Record check time
    date +%s > "$LAST_CHECK_FILE"

    local latest_ver
    latest_ver=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
    if [[ -z "$latest_ver" ]]; then
        log "No release tag found"
        return 1
    fi

    if ! semver_gt "$latest_ver" "$current_ver"; then
        log "Up to date (v${current_ver} >= v${latest_ver})"
        return 1
    fi

    local tarball_url
    tarball_url=$(echo "$api_response" | jq -r '.tarball_url // empty' 2>/dev/null)
    if [[ -z "$tarball_url" ]]; then
        log "No tarball URL in release"
        return 1
    fi

    log "New version available: v${latest_ver} (current: v${current_ver})"
    echo "${latest_ver}|${tarball_url}"
}

# Download and validate release artifacts
download_and_stage() {
    local version="$1" tarball_url="$2"
    log "Downloading v${version}"

    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

    # Download tarball — gh CLI for auth (private repos), curl fallback
    local tarball="${STAGING_DIR}/release.tar.gz"
    local dl_ok=false
    if command -v gh &>/dev/null; then
        gh api "$tarball_url" > "$tarball" 2>/dev/null && dl_ok=true
    fi
    if [[ "$dl_ok" != "true" ]]; then
        if ! curl --proto '=https' --tlsv1.2 --fail --silent --max-time 30 \
            -L -o "$tarball" "$tarball_url" 2>/dev/null; then
            log "Download failed"
            rm -rf "$STAGING_DIR"
            return 1
        fi
    fi

    # Extract (GitHub tarballs have a top-level directory)
    if ! tar xzf "$tarball" -C "$STAGING_DIR" 2>/dev/null; then
        log "Extraction failed"
        rm -rf "$STAGING_DIR"
        return 1
    fi
    rm -f "$tarball"

    # Find extracted directory
    local extracted
    extracted=$(find "$STAGING_DIR" -maxdepth 1 -type d ! -name staging | head -1)
    if [[ -z "$extracted" ]] || [[ "$extracted" == "$STAGING_DIR" ]]; then
        extracted=$(find "$STAGING_DIR" -maxdepth 1 -type d | tail -1)
    fi

    # Validate required files exist
    local required_files=(claude-pulse red-alert-daemon.sh update.sh)
    for f in "${required_files[@]}"; do
        if [[ ! -f "${extracted}/${f}" ]]; then
            log "Validation failed: missing ${f}"
            rm -rf "$STAGING_DIR"
            return 1
        fi
    done

    # Validate shell scripts: syntax check + shebang
    for f in "${required_files[@]}"; do
        local filepath="${extracted}/${f}"
        if ! bash -n "$filepath" 2>/dev/null; then
            log "Validation failed: syntax error in ${f}"
            rm -rf "$STAGING_DIR"
            return 1
        fi
        local shebang
        shebang=$(head -1 "$filepath")
        if [[ "$shebang" != "#!/bin/bash" ]]; then
            log "Validation failed: bad shebang in ${f}"
            rm -rf "$STAGING_DIR"
            return 1
        fi
    done

    # Move extracted files to staging root for easy access
    mv "${extracted}"/* "$STAGING_DIR/" 2>/dev/null || true
    find "$STAGING_DIR" -maxdepth 1 -type d -empty -delete 2>/dev/null || true

    log "Staged v${version} (validated)"
    echo "$version"
}

# Backup current files and apply update atomically
apply_update() {
    local version="$1"
    local current_ver
    current_ver=$(get_installed_version)
    log "Applying v${version} (backing up v${current_ver})"

    # Backup current files
    local backup_dir="${CACHE_DIR}/versions/v${current_ver}"
    mkdir -p "$backup_dir"
    for f in "${OTA_FILES[@]}"; do
        [[ -f "${CLAUDE_DIR}/${f}" ]] && cp "${CLAUDE_DIR}/${f}" "$backup_dir/"
    done
    cp "${CLAUDE_DIR}/"${OTA_STATIC_GLOB} "$backup_dir/" 2>/dev/null || true

    # Atomic swap: write to .tmp then mv (new inode, safe for running scripts)
    # statusline-command.sh <- claude-pulse
    if [[ -f "${STAGING_DIR}/claude-pulse" ]]; then
        cp "${STAGING_DIR}/claude-pulse" "${CLAUDE_DIR}/statusline-command.sh.tmp"
        chmod +x "${CLAUDE_DIR}/statusline-command.sh.tmp"
        mv -f "${CLAUDE_DIR}/statusline-command.sh.tmp" "${CLAUDE_DIR}/statusline-command.sh"
    fi

    # red-alert-daemon.sh
    if [[ -f "${STAGING_DIR}/red-alert-daemon.sh" ]]; then
        cp "${STAGING_DIR}/red-alert-daemon.sh" "${CLAUDE_DIR}/red-alert-daemon.sh.tmp"
        chmod +x "${CLAUDE_DIR}/red-alert-daemon.sh.tmp"
        mv -f "${CLAUDE_DIR}/red-alert-daemon.sh.tmp" "${CLAUDE_DIR}/red-alert-daemon.sh"
    fi

    # update.sh (self-update — safe because mv creates new inode)
    if [[ -f "${STAGING_DIR}/update.sh" ]]; then
        cp "${STAGING_DIR}/update.sh" "${CLAUDE_DIR}/update.sh.tmp"
        chmod +x "${CLAUDE_DIR}/update.sh.tmp"
        mv -f "${CLAUDE_DIR}/update.sh.tmp" "${CLAUDE_DIR}/update.sh"
    fi

    # Static assets
    mkdir -p "${CLAUDE_DIR}/static"
    cp "${STAGING_DIR}/"static/*.m4a "${CLAUDE_DIR}/static/" 2>/dev/null || true

    # Post-apply health check
    local new_ver
    new_ver=$(get_installed_version)
    if [[ "$new_ver" != "$version" ]]; then
        log "Health check failed: expected v${version}, got v${new_ver}"
        # Rollback
        for f in "${OTA_FILES[@]}"; do
            [[ -f "${backup_dir}/${f}" ]] && cp "${backup_dir}/${f}" "${CLAUDE_DIR}/${f}"
        done
        log "Rolled back to v${current_ver}"
        return 1
    fi

    # Request daemon restart (hook will handle it)
    echo "$version" > "${STATE_DIR}/daemon_restart_requested" 2>/dev/null

    # Write notification for statusline badge
    printf '%s\n%s' "$version" "$(date +%s)" > "${CACHE_DIR}/update_notification"

    # Clean up staging
    rm -rf "$STAGING_DIR"

    log "Applied v${version} successfully"
}

# Notify-only mode: stage but don't apply
notify_only() {
    local version="$1"
    log "Notify mode: v${version} available (staged at ${STAGING_DIR})"
    printf '%s\n%s' "$version" "${STAGING_DIR}" > "${CACHE_DIR}/update_available"
}

# Handle daemon restart marker (called from SessionStart hook context)
handle_daemon_restart() {
    local restart_file="${STATE_DIR}/daemon_restart_requested"
    if [[ -f "$restart_file" ]]; then
        rm -f "$restart_file"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            launchctl kickstart -k "gui/$(id -u)/com.claude-pulse.red-alert" 2>/dev/null || true
        fi
        log "Daemon restart triggered"
    fi
}

# --- Main ---

# Always handle pending daemon restarts first
handle_daemon_restart

current_ver=$(get_installed_version)
if [[ -z "$current_ver" ]]; then
    log "Could not determine installed version"
    exit 0
fi

result=$(check_update "$current_ver") || exit 0

IFS='|' read -r new_ver tarball_url <<< "$result"

staged_ver=$(download_and_stage "$new_ver" "$tarball_url") || exit 1

if [[ "$UPDATE_MODE" == "notify" ]]; then
    notify_only "$staged_ver"
else
    apply_update "$staged_ver"
fi
