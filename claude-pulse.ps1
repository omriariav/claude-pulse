# claude-pulse.ps1 v1.3.1: Real-time token usage for Claude Code status line (Windows)
# Uses billing API (transcript) for accurate FULL context usage
# Falls back to native context_window when transcript unavailable

# Read JSON from stdin
$inputJson = [Console]::In.ReadToEnd()
$data = $inputJson | ConvertFrom-Json

$cwd = $data.cwd
$context_limit = 200000

# Primary: Billing API from transcript (includes ALL context: messages + system + MCP tools)
# Sum: input_tokens + cache_creation_input_tokens + cache_read_input_tokens
# This matches what /context shows
if ($data.transcript_path -and (Test-Path $data.transcript_path)) {
    $session_id = $data.session_id
    $lines = Get-Content $data.transcript_path | ForEach-Object { $_ | ConvertFrom-Json }
    $usage = $lines | Where-Object { $_.sessionId -eq $session_id -and $_.message.usage } | Select-Object -Last 1
    if ($usage) {
        $u = $usage.message.usage
        $input_tokens = ($u.input_tokens ?? 0) + ($u.cache_creation_input_tokens ?? 0) + ($u.cache_read_input_tokens ?? 0)
    }
}

# Fallback: Native context_window (conversation only, missing MCP/system overhead)
if ($null -eq $input_tokens -and $null -ne $data.context_window -and $null -ne $data.context_window.total_input_tokens) {
    $input_tokens = $data.context_window.total_input_tokens + $data.context_window.total_output_tokens
    if ($null -ne $data.context_window.context_window_size) {
        $context_limit = $data.context_window.context_window_size
    }
}

# No data available
if ($null -eq $input_tokens) {
    if (-not $data.transcript_path -or -not (Test-Path $data.transcript_path)) {
        Write-Host "Transcript not found"
        Write-Host $cwd
        exit 0
    }
    Write-Host "No token usage yet"
    Write-Host $cwd
    exit 0
}

# Calculate percentage
$percent = [math]::Floor(($input_tokens / $context_limit) * 100)

# Format with K notation
if ($input_tokens -ge 1000) {
    $tokens_fmt = "{0}k" -f [math]::Floor($input_tokens / 1000)
} else {
    $tokens_fmt = $input_tokens
}

if ($context_limit -ge 1000) {
    $limit_fmt = "{0}k" -f [math]::Floor($context_limit / 1000)
} else {
    $limit_fmt = $context_limit
}

# Color based on percentage
if ($percent -ge 80) {
    $color = "`e[31m"  # Red
} elseif ($percent -ge 50) {
    $color = "`e[33m"  # Yellow
} else {
    $color = "`e[32m"  # Green
}
$reset = "`e[0m"

# Output
Write-Host "${color}$tokens_fmt/$limit_fmt (${percent}%)${reset}"
Write-Host $cwd
