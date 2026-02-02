# claude-pulse.ps1 v1.5.0: Real-time token usage for Claude Code status line (Windows)
# Uses billing API (transcript) for accurate FULL context usage
# Falls back to native context_window when transcript unavailable
# Displays current model name and AI-generated conversation names
# Supports Anthropic, OpenAI, and Gemini APIs for name generation

# Read JSON from stdin
$inputJson = [Console]::In.ReadToEnd()
$data = $inputJson | ConvertFrom-Json

$cwd = $data.cwd
$model_id = if ($data.model.id) { $data.model.id } else { "claude-sonnet-4-5-20250929" }

# Convert model ID to friendly name
$model_name = switch -Wildcard ($model_id) {
    "claude-opus-4*" { "Opus 4.5"; break }
    "claude-sonnet-4*" { "Sonnet 4.5"; break }
    "claude-haiku-3-5*" { "Haiku 3.5"; break }
    "claude-3-5-haiku*" { "Haiku 3.5"; break }
    "claude-sonnet-3-5*" { "Sonnet 3.5"; break }
    "claude-3-5-sonnet*" { "Sonnet 3.5"; break }
    "claude-opus-3*" { "Opus 3"; break }
    "claude-3-opus*" { "Opus 3"; break }
    "claude-sonnet-3-7*" { "Sonnet 3.7"; break }
    "claude-3-7-sonnet*" { "Sonnet 3.7"; break }
    default { "Claude" }
}

$context_limit = 200000

# Check for actual context window size from JSON (overrides hardcoded default)
if ($null -ne $data.context_window -and $null -ne $data.context_window.context_window_size) {
    $context_limit = $data.context_window.context_window_size
}

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
        Write-Host "🧠 Transcript not found 📁 $cwd"
        exit 0
    }
    Write-Host "🧠 No token usage yet 📁 $cwd"
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

# Conversation name lookup
$conv_name = ""
if ($data.transcript_path -and $data.session_id) {
    $project_dir = Split-Path $data.transcript_path -Parent
    $sessions_index = Join-Path $project_dir "sessions-index.json"
    $cache_dir = Join-Path $HOME ".cache" "claude-pulse"

    if (Test-Path $sessions_index) {
        $sessions = Get-Content $sessions_index | ConvertFrom-Json
        $session = $sessions.entries | Where-Object { $_.sessionId -eq $data.session_id } | Select-Object -First 1

        if ($session -and $session.summary) {
            $summary = $session.summary
            $cache_file = Join-Path $cache_dir "$($data.session_id).name"
            $hasher = [System.Security.Cryptography.MD5]::Create()
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($summary)
            $summary_hash = [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace("-","").ToLower()

            # Check cache
            if (Test-Path $cache_file) {
                $cached = Get-Content $cache_file
                if ($cached[0] -eq $summary_hash) {
                    $conv_name = $cached[1]
                }
            }

            # Generate name if not cached
            if (-not $conv_name) {
                # Try Anthropic API
                if ($env:ANTHROPIC_API_KEY) {
                    try {
                        $body = @{
                            model = "claude-haiku-4-5-20251001"
                            max_tokens = 20
                            messages = @(@{
                                role = "user"
                                content = "Generate a 2-3 word short name for this conversation topic. Reply with ONLY the short name, nothing else: $summary"
                            })
                        } | ConvertTo-Json -Depth 3
                        $headers = @{
                            "content-type" = "application/json"
                            "x-api-key" = $env:ANTHROPIC_API_KEY
                            "anthropic-version" = "2023-06-01"
                        }
                        $resp = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers $headers -Body $body -TimeoutSec 3
                        $conv_name = $resp.content[0].text
                    } catch {}
                }

                # Try OpenAI API
                if (-not $conv_name -and $env:OPENAI_API_KEY) {
                    try {
                        $body = @{
                            model = "gpt-4o-mini"
                            max_tokens = 20
                            messages = @(@{
                                role = "user"
                                content = "Generate a 2-3 word short name for this conversation topic. Reply with ONLY the short name, nothing else: $summary"
                            })
                        } | ConvertTo-Json -Depth 3
                        $headers = @{
                            "content-type" = "application/json"
                            "authorization" = "Bearer $env:OPENAI_API_KEY"
                        }
                        $resp = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers $headers -Body $body -TimeoutSec 3
                        $conv_name = $resp.choices[0].message.content
                    } catch {}
                }

                # Try Gemini API
                if (-not $conv_name -and $env:GEMINI_API_KEY) {
                    try {
                        $body = @{
                            contents = @(@{
                                parts = @(@{
                                    text = "Generate a 2-3 word short name for this conversation topic. Reply with ONLY the short name, nothing else: $summary"
                                })
                            })
                        } | ConvertTo-Json -Depth 3
                        $headers = @{
                            "content-type" = "application/json"
                        }
                        $resp = Invoke-RestMethod -Uri "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$env:GEMINI_API_KEY" -Method Post -Headers $headers -Body $body -TimeoutSec 3
                        $conv_name = $resp.candidates[0].content.parts[0].text
                    } catch {}
                }

                # Fallback: first 3 words
                if (-not $conv_name) {
                    $words = $summary -split '\s+' | Select-Object -First 3
                    $conv_name = $words -join ' '
                }

                # Cache the result
                if (-not (Test-Path $cache_dir)) { New-Item -ItemType Directory -Path $cache_dir -Force | Out-Null }
                @($summary_hash, $conv_name) | Set-Content $cache_file
            }
        }
    }
}

# Build name segment
$name_segment = ""
if ($conv_name) {
    $name_segment = " · 💬 `"$conv_name`""
}

# Output format: "🧠 64k/200k (32%) · Sonnet 4.5 · name 📁 /path" - all on one line
Write-Host "${color}🧠 $tokens_fmt/$limit_fmt (${percent}%) · 🤖 ${model_name}${name_segment}${reset} 📁 $cwd"
