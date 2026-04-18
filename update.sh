#!/bin/bash
# claude-pulse update.sh v3.1.3: OTA update manager
# Checks GitHub releases, downloads, validates, and applies updates atomically
# Triggered by SessionStart hook — runs in background, singleton-locked

set -euo pipefail
umask 077

REPO="omriariav/claude-pulse"
CLAUDE_DIR="$HOME/.claude"
CACHE_DIR="$HOME/.cache/claude-pulse"
STATE_DIR="$HOME/.local/state/claude-pulse"
STAGING_DIR="${CACHE_DIR}/staging"
LOG_FILE="${STATE_DIR}/update.log"

# Pinned allowed hosts for artifact downloads (prevents open redirect attacks)
ALLOWED_HOSTS="github.com api.github.com"

# Files managed by OTA
OTA_FILES=(statusline-command.sh red-alert-daemon.sh update.sh)
OTA_STATIC_GLOB="static/*.m4a"

# Update mode: auto (default) or notify
UPDATE_MODE="${CLAUDE_PULSE_AUTO_UPDATE:-auto}"

mkdir -p "$CACHE_DIR" "$STATE_DIR" 2>/dev/null
chmod 700 "$CACHE_DIR" "$STATE_DIR" 2>/dev/null

log() { printf '%s [update] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE" 2>/dev/null; }

# Validate URL against pinned allowed hosts (strips port for comparison)
_validate_url() {
    local url="$1"
    local host
    host=$(echo "$url" | sed -n 's|^https\{0,1\}://\([^/:]*\).*|\1|p')
    for allowed in $ALLOWED_HOSTS; do
        [[ "$host" == "$allowed" ]] && return 0
    done
    log "Blocked download from untrusted host: ${host}"
    return 1
}

# Singleton lock — only one update.sh runs at a time
# Stale lock recovery: if lock is older than 10 minutes, reclaim it
LOCK_DIR="${CACHE_DIR}/update.lock"
LOCK_TTL=600
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    if [[ -d "$LOCK_DIR" ]]; then
        lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
        if (( lock_age > LOCK_TTL )); then
            log "Reclaiming stale update lock (age: ${lock_age}s)"
            rm -rf "$LOCK_DIR"
            mkdir "$LOCK_DIR" 2>/dev/null || exit 0
        else
            exit 0
        fi
    else
        exit 0
    fi
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

    # Prefer uploaded release assets (tarball + checksums) over GitHub auto-generated tarball
    local tarball_url checksum_url=""
    tarball_url=$(echo "$api_response" | jq -r '
        .assets[]? | select(.name | test("claude-pulse.*\\.tar\\.gz$")) | .browser_download_url
    ' 2>/dev/null | head -1)
    checksum_url=$(echo "$api_response" | jq -r '
        .assets[]? | select(.name | test("checksums\\.sha256$")) | .browser_download_url
    ' 2>/dev/null | head -1)

    # Fallback to GitHub auto-generated tarball (no checksum available)
    if [[ -z "$tarball_url" ]]; then
        tarball_url=$(echo "$api_response" | jq -r '.tarball_url // empty' 2>/dev/null)
    fi
    if [[ -z "$tarball_url" ]]; then
        log "No tarball URL in release"
        return 1
    fi

    log "New version available: v${latest_ver} (current: v${current_ver})"
    echo "${latest_ver}|${tarball_url}|${checksum_url}"
}

# Download a URL using gh CLI (private repos) with curl fallback
# Validates URL against ALLOWED_HOSTS before downloading
_download() {
    local url="$1" dest="$2"
    _validate_url "$url" || return 1
    local ok=false
    if command -v gh &>/dev/null; then
        gh api "$url" > "$dest" 2>/dev/null && [[ -s "$dest" ]] && ok=true
    fi
    if [[ "$ok" != "true" ]]; then
        curl --proto '=https' --tlsv1.2 --fail --silent --max-time 30 \
            -L -o "$dest" "$url" 2>/dev/null || return 1
    fi
}

# Download and validate release artifacts
download_and_stage() {
    local version="$1" tarball_url="$2" checksum_url="${3:-}"
    log "Downloading v${version}"

    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

    # Download tarball
    local tarball="${STAGING_DIR}/release.tar.gz"
    if ! _download "$tarball_url" "$tarball"; then
        log "Download failed"
        rm -rf "$STAGING_DIR"
        return 1
    fi

    # SHA256 verification — fail closed (no checksum = no update)
    if [[ -z "$checksum_url" ]]; then
        log "Aborted: release has no checksum asset (unsigned releases not accepted)"
        rm -rf "$STAGING_DIR"
        return 1
    fi

    local checksum_file="${STAGING_DIR}/checksums.sha256"
    if ! _download "$checksum_url" "$checksum_file"; then
        log "Aborted: could not download checksum file"
        rm -rf "$STAGING_DIR"
        return 1
    fi

    local expected_hash actual_hash
    expected_hash=$(grep -o '^[a-f0-9]\{64\}' "$checksum_file" | head -1)
    actual_hash=$(shasum -a 256 "$tarball" 2>/dev/null | cut -d' ' -f1)
    if [[ -z "$expected_hash" ]]; then
        log "Aborted: checksum file malformed"
        rm -rf "$STAGING_DIR"
        return 1
    fi
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        log "Aborted: checksum mismatch — expected ${expected_hash}, got ${actual_hash}"
        rm -rf "$STAGING_DIR"
        return 1
    fi
    log "Checksum verified (SHA256: ${actual_hash:0:16}...)"

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

    # Mark apply in-progress (crash recovery: next run detects incomplete apply)
    local apply_marker="${CACHE_DIR}/apply_in_progress"
    printf '%s\n%s' "$version" "$current_ver" > "$apply_marker"

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

    # Management skills (slash commands)
    mkdir -p "${CLAUDE_DIR}/commands"
    cp "${STAGING_DIR}/"commands/*.md "${CLAUDE_DIR}/commands/" 2>/dev/null || true

    # Post-apply health check — verify all versioned files updated
    local new_ver check_ok=true
    new_ver=$(get_installed_version)
    [[ "$new_ver" != "$version" ]] && check_ok=false
    local daemon_ver
    daemon_ver=$(sed -n '2s/.*v\([0-9.]*\).*/\1/p' "${CLAUDE_DIR}/red-alert-daemon.sh" 2>/dev/null)
    [[ -n "$daemon_ver" ]] && [[ "$daemon_ver" != "$version" ]] && check_ok=false

    if [[ "$check_ok" != "true" ]]; then
        log "Health check failed: expected v${version}, got statusline=v${new_ver} daemon=v${daemon_ver}"
        # Rollback all files from backup
        for f in "${OTA_FILES[@]}"; do
            [[ -f "${backup_dir}/${f}" ]] && cp "${backup_dir}/${f}" "${CLAUDE_DIR}/${f}"
        done
        rm -f "$apply_marker"
        log "Rolled back to v${current_ver}"
        return 1
    fi

    # Request daemon restart (hook will handle it)
    echo "$version" > "${STATE_DIR}/daemon_restart_requested" 2>/dev/null

    # Write notification for statusline badge and clear any stale notify-mode badge
    printf '%s\n%s' "$version" "$(date +%s)" > "${CACHE_DIR}/update_notification"
    rm -f "${CACHE_DIR}/update_available"

    # Clean up staging and apply marker
    rm -rf "$STAGING_DIR"
    rm -f "$apply_marker"

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

# Crash recovery: if a previous apply was interrupted, rollback from backup
_apply_marker="${CACHE_DIR}/apply_in_progress"
if [[ -f "$_apply_marker" ]]; then
    _target_ver=$(head -1 "$_apply_marker" 2>/dev/null)
    _backup_ver=$(tail -1 "$_apply_marker" 2>/dev/null)
    _backup_dir="${CACHE_DIR}/versions/v${_backup_ver}"
    if [[ -d "$_backup_dir" ]]; then
        log "Crash recovery: incomplete apply of v${_target_ver} detected, rolling back to v${_backup_ver}"
        for f in "${OTA_FILES[@]}"; do
            [[ -f "${_backup_dir}/${f}" ]] && cp "${_backup_dir}/${f}" "${CLAUDE_DIR}/${f}"
        done
    fi
    rm -f "$_apply_marker"
fi

# Always handle pending daemon restarts first
handle_daemon_restart

current_ver=$(get_installed_version)
if [[ -z "$current_ver" ]]; then
    log "Could not determine installed version"
    exit 0
fi

# If a staged update exists (notify mode) and we're now in auto mode, apply it directly
_avail_file="${CACHE_DIR}/update_available"
if [[ "$UPDATE_MODE" == "auto" ]] && [[ -f "$_avail_file" ]]; then
    _staged_ver=$(head -1 "$_avail_file" 2>/dev/null)
    _staged_dir=$(tail -1 "$_avail_file" 2>/dev/null)
    if [[ -n "$_staged_ver" ]] && [[ -d "$_staged_dir" ]]; then
        log "Applying previously staged v${_staged_ver}"
        STAGING_DIR="$_staged_dir"
        apply_update "$_staged_ver" && exit 0
    fi
    # Staged dir gone — clean up stale marker
    rm -f "$_avail_file"
fi

result=$(check_update "$current_ver") || exit 0

IFS='|' read -r new_ver tarball_url checksum_url <<< "$result"

staged_ver=$(download_and_stage "$new_ver" "$tarball_url" "$checksum_url") || exit 1

if [[ "$UPDATE_MODE" == "notify" ]]; then
    notify_only "$staged_ver"
else
    apply_update "$staged_ver"
fi
