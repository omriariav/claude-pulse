# claude-pulse.ps1 v3.3.0: Real-time token usage for Claude Code status line (Windows)
# Uses billing API (transcript) for accurate FULL context usage
# Falls back to native context_window when transcript unavailable
# Displays current model name and AI-generated conversation names
# Supports Anthropic, OpenAI, and Gemini APIs for name generation

# Read JSON from stdin
$inputJson = [Console]::In.ReadToEnd()
$data = $inputJson | ConvertFrom-Json

$cwd = $data.cwd
$model_id = if ($data.model.id) { $data.model.id } else { "claude-sonnet-4-5-20250929" }
$display_name = if ($data.model.display_name) { $data.model.display_name } else { "" }

# Convert model ID to friendly name.
#
# The modern naming scheme is regular — claude-<family>-<major>-<minor> — so we
# parse it generically and NEVER need a new branch per release (Opus 4.8, a
# future Sonnet 5.0, etc. all "just work"). Only the irregular legacy IDs need
# explicit rows, and anything unknown defers to Claude Code's own display_name.
$model_name = $null
if ($model_id -match '^claude-(opus|sonnet|haiku)-([0-9]+)-([0-9]{1,2})(?![0-9])') {
    # The (?![0-9]) guard rejects 8-digit release dates (claude-opus-4-20250512),
    # letting those fall through to the legacy table below.
    $family = switch ($matches[1]) {
        "opus"   { "Opus" }
        "sonnet" { "Sonnet" }
        "haiku"  { "Haiku" }
    }
    $model_name = "$family $($matches[2]).$($matches[3])"
}

if (-not $model_name) {
    # Legacy / irregular IDs only — modern releases are handled above.
    $model_name = switch -Wildcard ($model_id) {
        "claude-opus-4*" { "Opus 4.5"; break }
        "claude-sonnet-4*" { "Sonnet 4.5"; break }
        "claude-4-5-haiku*" { "Haiku 4.5"; break }
        "claude-3-5-haiku*" { "Haiku 3.5"; break }
        "claude-3-5-sonnet*" { "Sonnet 3.5"; break }
        "claude-opus-3*" { "Opus 3"; break }
        "claude-3-opus*" { "Opus 3"; break }
        "claude-3-7-sonnet*" { "Sonnet 3.7"; break }
        default { if ($display_name) { $display_name } else { "Claude" } }
    }
}

# Short model label for compact densities (Opus 4.8 -> Op4.8, Sonnet 3.7 -> Son3.7)
$model_short = $model_name -replace '^Opus ', 'Op' -replace '^Sonnet ', 'Son' -replace '^Haiku ', 'Hai'

# Rate limits / cost / effort (Pro/Max + recent Claude Code only; null when absent)
$rate_5h = $data.rate_limits.five_hour.used_percentage
$rate_7d = $data.rate_limits.seven_day.used_percentage
$cost_usd = $data.cost.total_cost_usd
$effort = $data.effort.level

$context_limit = 200000

# Check for actual context window size from JSON (overrides hardcoded default)
if ($null -ne $data.context_window -and $null -ne $data.context_window.context_window_size) {
    $context_limit = $data.context_window.context_window_size
}

# Format context limit for display (200000 → "200k", 1000000 → "1M")
if ($context_limit -ge 1000000 -and $context_limit % 1000000 -eq 0) {
    $context_label = "$([math]::Floor($context_limit / 1000000))M"
} else {
    $context_label = "$([math]::Floor($context_limit / 1000))k"
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
$percent = [math]::Round(($input_tokens / $context_limit) * 100)

# Cap percentage for display
$display_percent = [math]::Min($percent, 100)

# Progress bar (20-char, shows context consumed)
$bar_width = 20
$bar_filled = [math]::Floor(($display_percent * $bar_width + 50) / 100)
if ($bar_filled -gt $bar_width) { $bar_filled = $bar_width }
if ($bar_filled -lt 0) { $bar_filled = 0 }
$bar_empty = $bar_width - $bar_filled

$bar = "[" + ("█" * $bar_filled) + ("░" * $bar_empty) + "]"

# Color based on usage (green=low, yellow=moderate, red=high)
if ($percent -ge 80) {
    $color = "`e[31m"  # Red — running high
} elseif ($percent -ge 50) {
    $color = "`e[33m"  # Yellow — moderate usage
} else {
    $color = "`e[32m"  # Green — plenty of room
}
$reset = "`e[0m"

# Cache directory for conversation names and PR lookups
$cache_dir = Join-Path $HOME ".cache" "claude-pulse"

# Generate a short name via AI APIs
function Get-ConversationName {
    param([string]$Prompt)
    $name = ""

    # Try Anthropic API
    if ($env:ANTHROPIC_API_KEY) {
        try {
            $body = @{
                model = "claude-haiku-4-5-20251001"
                max_tokens = 20
                messages = @(@{ role = "user"; content = $Prompt })
            } | ConvertTo-Json -Depth 3
            $headers = @{
                "content-type" = "application/json"
                "x-api-key" = $env:ANTHROPIC_API_KEY
                "anthropic-version" = "2023-06-01"
            }
            $resp = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers $headers -Body $body -TimeoutSec 3
            $name = $resp.content[0].text
        } catch {}
    }

    # Try OpenAI API
    if (-not $name -and $env:OPENAI_API_KEY) {
        try {
            $body = @{
                model = "gpt-4o-mini"
                max_tokens = 20
                messages = @(@{ role = "user"; content = $Prompt })
            } | ConvertTo-Json -Depth 3
            $headers = @{
                "content-type" = "application/json"
                "authorization" = "Bearer $env:OPENAI_API_KEY"
            }
            $resp = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers $headers -Body $body -TimeoutSec 3
            $name = $resp.choices[0].message.content
        } catch {}
    }

    # Try Gemini API
    if (-not $name -and $env:GEMINI_API_KEY) {
        try {
            $body = @{
                contents = @(@{ parts = @(@{ text = $Prompt }) })
            } | ConvertTo-Json -Depth 3
            $headers = @{
                "content-type" = "application/json"
                "x-goog-api-key" = $env:GEMINI_API_KEY
            }
            $resp = Invoke-RestMethod -Uri "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" -Method Post -Headers $headers -Body $body -TimeoutSec 3
            $name = $resp.candidates[0].content.parts[0].text
        } catch {}
    }

    return $name
}

# Conversation name lookup
$conv_name = ""

# Primary: session_name from Claude Code (native field, available after /rename or auto-generated)
if ($data.session_name) {
    $conv_name = $data.session_name
# Fallback: AI-generated name from transcript/sessions-index (for older Claude Code versions)
} elseif ($data.transcript_path -and $data.session_id) {
    $project_dir = Split-Path $data.transcript_path -Parent
    $sessions_index = Join-Path $project_dir "sessions-index.json"
    $cache_file = Join-Path $cache_dir "$($data.session_id).name"

    # Source 1: Session summary from sessions-index.json (set by /rename or conversation end)
    $summary = ""
    if (Test-Path $sessions_index) {
        $sessions = Get-Content $sessions_index | ConvertFrom-Json
        $session = $sessions.entries | Where-Object { $_.sessionId -eq $data.session_id } | Select-Object -First 1
        if ($session -and $session.summary) {
            $summary = $session.summary
        }
    }

    # Source 2: Infer from first assistant messages in transcript (for active sessions without summary)
    if (-not $summary -and (Test-Path $data.transcript_path)) {
        $lines = Get-Content $data.transcript_path | ForEach-Object { $_ | ConvertFrom-Json }
        $assistantTexts = $lines | Where-Object { $_.type -eq "assistant" } | ForEach-Object {
            $_.message.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1 -ExpandProperty text
        } | Where-Object { $_ } | Select-Object -First 3
        if ($assistantTexts) {
            $summary = ($assistantTexts -join " ").Substring(0, [Math]::Min(300, ($assistantTexts -join " ").Length))
        }
    }

    if ($summary) {
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
            $prompt = "Generate a 2-3 word short name for this conversation topic. Reply with ONLY the short name, nothing else: $summary"
            $conv_name = Get-ConversationName -Prompt $prompt

            # Fallback: first 3 words
            if (-not $conv_name) {
                $words = $summary -split '\s+' | Select-Object -First 3
                $conv_name = $words -join ' '
            }

            # Cache the result atomically (only if valid)
            if ($conv_name -and $conv_name -ne "null") {
                if (-not (Test-Path $cache_dir)) {
                    New-Item -ItemType Directory -Path $cache_dir -Force | Out-Null
                    $acl = Get-Acl $cache_dir
                    $acl.SetAccessRuleProtection($true, $false)
                    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                    $acl.SetAccessRule($rule)
                    Set-Acl $cache_dir $acl
                }
                $tmp_file = "$cache_file.$PID"
                @($summary_hash, $conv_name) | Set-Content $tmp_file
                Move-Item -Path $tmp_file -Destination $cache_file -Force
            }
        }
    }
}

# Truncate long conversation names
if ($conv_name -and $conv_name.Length -gt 20) {
    $conv_name = $conv_name.Substring(0, 18) + ".."
}

# Build name segment
$name_segment = ""
if ($conv_name) {
    $name_segment = " · 💬 $conv_name"
}

# Git branch detection
$branch = ""
try {
    $branch = git -C $cwd branch --show-current 2>$null
} catch {}

# Git diff stats (files changed, insertions, deletions)
$diff_segment = ""
$is_git_repo = $false
try { $is_git_repo = (git -C $cwd rev-parse --is-inside-work-tree 2>$null) -eq "true" } catch {}
if ($is_git_repo -and -not $env:CLAUDE_PULSE_HIDE_DIFF) {
    $diff_stat = & { $env:LC_ALL = "C"; git -C $cwd diff HEAD --shortstat 2>$null }
    if ($diff_stat) {
        $df = 0; $di = 0; $dd = 0
        if ($diff_stat -match '(\d+) file') { $df = [int]$Matches[1] }
        if ($diff_stat -match '(\d+) insertion') { $di = [int]$Matches[1] }
        if ($diff_stat -match '(\d+) deletion') { $dd = [int]$Matches[1] }
        if ($df -gt 0) {
            $cyan = "`e[38;2;139;233;253m"
            $fl = if ($df -eq 1) { "file" } else { "files" }
            $plus = if ($di -gt 0) { "`e[38;2;80;250;123m+$di`e[0m" } else { "" }
            $minus = if ($dd -gt 0) { "`e[38;2;255;85;85m-$dd`e[0m" } else { "" }
            $ch = @($plus, $minus) | Where-Object { $_ } | Join-String -Separator " "
            $ch_suffix = if ($ch) { " $ch" } else { "" }
            $diff_segment = " · 📝 ${cyan}${df} ${fl}`e[0m${ch_suffix}"
        }
    }
}

# Git branch + PR number segment
$pr_segment = ""
if ($branch) {
    $pr_segment = " · 🌿 $branch"

    # PR lookup with caching (only if gh is available and not on main/master)
    if ((Get-Command gh -ErrorAction SilentlyContinue) -and $branch -ne "main" -and $branch -ne "master") {
        $cwd_hash = [BitConverter]::ToString(
            [System.Security.Cryptography.MD5]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($cwd)
            )
        ).Replace("-","").ToLower()
        # Sanitize branch name for safe cache filename (feat/bar -> feat-bar)
        $safe_branch = $branch -replace '/', '-'
        $pr_cache_file = Join-Path $cache_dir "pr-$cwd_hash-$safe_branch"
        $pr_number = ""

        # Check cache (valid for 10 min)
        if (Test-Path $pr_cache_file) {
            $cache_age = ((Get-Date) - (Get-Item $pr_cache_file).LastWriteTime).TotalSeconds
            if ($cache_age -lt 600) {
                $pr_number = Get-Content $pr_cache_file -Raw
            }
        }

        # Fetch PR number if not cached (with 1s timeout)
        if (-not $pr_number) {
            try {
                $job = Start-Job { gh pr view --json number -q .number 2>$null }
                $completed = $job | Wait-Job -Timeout 1
                if ($completed) { $pr_number = Receive-Job $job }
                Remove-Job $job -Force
            } catch {}
            if (-not $pr_number) { $pr_number = "none" }
            if (-not (Test-Path $cache_dir)) {
                New-Item -ItemType Directory -Path $cache_dir -Force | Out-Null
            }
            $tmp_file = "$pr_cache_file.$PID"
            Set-Content -Path $tmp_file -Value $pr_number -NoNewline
            Move-Item -Path $tmp_file -Destination $pr_cache_file -Force
        }

        if ($pr_number -and $pr_number -ne "none") {
            $pr_segment = " · 🌿 $branch (#$pr_number)"
        }
    }
}

# Red Alert: read-only — daemon is managed by launchd (macOS) or systemd (Linux)
$alert_segment = ""
if ($env:RED_ALERT_CITIES -or $env:RED_ALERT_MODE) {
    # State/PID files use user-owned directory
    $state_dir = if ($IsWindows) { Join-Path $env:LOCALAPPDATA "claude-pulse" } else { Join-Path $HOME ".local" "state" "claude-pulse" }
    $state_file = Join-Path $state_dir "red_alert_state.json"
    $pid_file = Join-Path $state_dir "red_alert_daemon.pid"

    if (Test-Path $state_file) {
        try {
            $alert_data = Get-Content $state_file -Raw -ErrorAction Stop | ConvertFrom-Json
        } catch {
            $alert_data = $null
        }
        if ($alert_data) {
            $alert_cat = $alert_data.cat
            $alert_last_seen = [int]$alert_data.last_seen_unix
        $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

        # Determine if alert is active (within persistence windows)
        $alert_active = $false
        if ($alert_cat -and $alert_cat -ne "" -and $alert_cat -ne "null") {
            $age = $now - $alert_last_seen
            switch ($alert_cat) {
                "13" { if ($age -le 15) { $alert_active = $true } }    # All clear: 15s
                "14" { if ($age -le 1200) { $alert_active = $true } }  # Pre-alert: 20 min
                default { if ($age -le 60) { $alert_active = $true } } # Active: 60s
            }
        }

        if ($alert_active) {
            # Get alert icon and label
            switch ($alert_cat) {
                "1"   { $alert_icon = "🚀"; $alert_label = "MISSILES" }
                "2"   { $alert_icon = "✈️";  $alert_label = "AIRCRAFT" }
                "3"   { $alert_icon = "🌍"; $alert_label = "EARTHQUAKE" }
                "4"   { $alert_icon = "🌊"; $alert_label = "TSUNAMI" }
                "5"   { $alert_icon = "☢️";  $alert_label = "RADIOLOGICAL" }
                "6"   { $alert_icon = "✈️";  $alert_label = "UAV" }
                "7"   { $alert_icon = "🔫"; $alert_label = "INFILTRATION" }
                "13"  { $alert_icon = "✅"; $alert_label = "ALL CLEAR" }
                "14"  { $alert_icon = "⚠️";  $alert_label = "PRE-ALERT" }
                { $_ -match '^10[1-7]$' } { $alert_icon = "🔔"; $alert_label = "DRILL" }
                default { $alert_icon = "⚠️";  $alert_label = "ALERT" }
            }

            # City name mapping (English → Hebrew)
            $city_map = @{
                "tel aviv" = "תל אביב"; "ramat gan" = "רמת גן"; "jerusalem" = "ירושלים"
                "haifa" = "חיפה"; "beer sheva" = "באר שבע"; "beersheba" = "באר שבע"
                "beersheva" = "באר שבע"; "ashdod" = "אשדוד"; "ashkelon" = "אשקלון"
                "netanya" = "נתניה"; "herzliya" = "הרצליה"; "petah tikva" = "פתח תקווה"
                "rishon lezion" = "ראשון לציון"; "holon" = "חולון"; "bat yam" = "בת ים"
                "bnei brak" = "בני ברק"; "rehovot" = "רחובות"; "kfar saba" = "כפר סבא"
                "ra'anana" = "רעננה"; "raanana" = "רעננה"; "modiin" = "מודיעין"
                "eilat" = "אילת"; "nazareth" = "נצרת"; "acre" = "עכו"; "akko" = "עכו"
                "tiberias" = "טבריה"; "sderot" = "שדרות"; "kiryat shmona" = "קריית שמונה"
                "nahariya" = "נהריה"; "lod" = "לוד"; "ramla" = "רמלה"
                "givatayim" = "גבעתיים"; "hod hasharon" = "הוד השרון"
            }

            # Prefer English city names, fall back to Hebrew
            if ($alert_data.cities_en -and $alert_data.cities_en.Count -gt 0) {
                $all_cities = @($alert_data.cities_en)
            } else {
                $all_cities = @($alert_data.cities)
            }

            # City filtering (unless mode=all)
            if ($env:RED_ALERT_MODE -eq "all" -or -not $env:RED_ALERT_CITIES) {
                $filtered_cities = $all_cities
            } else {
                $filters = $env:RED_ALERT_CITIES -split ',' | ForEach-Object { $_.Trim().ToLower() }
                $filtered_cities = @()
                foreach ($city in $all_cities) {
                    if (-not $city) { continue }
                    foreach ($filter in $filters) {
                        $hebrew = $city_map[$filter]
                        if ($hebrew -and $city -match [regex]::Escape($hebrew)) {
                            $filtered_cities += $city; break
                        }
                        if ($city.ToLower() -match [regex]::Escape($filter)) {
                            $filtered_cities += $city; break
                        }
                    }
                }
            }

            # Build alert display
            $red_bg = "`e[41;97m"
            if ($filtered_cities.Count -gt 0 -or $alert_cat -eq "13" -or $alert_cat -eq "14") {
                if ($filtered_cities.Count -le 3) {
                    $city_display = $filtered_cities -join " · "
                    if ($city_display) {
                        $alert_segment = "`n${red_bg} ${alert_icon} ${alert_label} · ${city_display} ${reset}"
                    } else {
                        $alert_segment = "`n${red_bg} ${alert_icon} ${alert_label} ${reset}"
                    }
                } else {
                    $cycle_index = [math]::Floor($now / 2) % $filtered_cities.Count
                    $cycling_city = $filtered_cities[$cycle_index]
                    $count = $filtered_cities.Count
                    $alert_segment = "`n${red_bg} ${alert_icon} ${alert_label} · ${count} cities · ${cycling_city} ${reset}"
                }
            }
        }
        } # end if ($alert_data)
    }

    # Alert status indicator on 2nd line
    if (-not $alert_segment) {
        if ((Test-Path $pid_file) -and (Get-Content $pid_file -ErrorAction SilentlyContinue) -and
            (try { Get-Process -Id (Get-Content $pid_file) -ErrorAction Stop; $true } catch { $false })) {
            $alert_segment = "`n`e[32m🟢 Alerts daemon ON${reset}"
        } else {
            $alert_segment = "`n`e[90m🔕 Alerts daemon not running${reset}"
        }
    }
}

# Taboola density — single line, reference's 16-color ANSI palette (theme-adaptive),
# NO_COLOR honored. Mirrors the bash `taboola` branch. Opt-in via CLAUDE_PULSE_DENSITY=taboola.
if ($env:CLAUDE_PULSE_DENSITY -eq 'taboola') {
    if (-not $env:NO_COLOR) {
        $tRst = "`e[0m"; $tDim = "`e[2m"; $tRed = "`e[31m"; $tGrn = "`e[32m"
        $tYel = "`e[33m"; $tBlu = "`e[34m"; $tCyn = "`e[36m"
    } else {
        $tRst = ""; $tDim = ""; $tRed = ""; $tGrn = ""; $tYel = ""; $tBlu = ""; $tCyn = ""
    }
    $tSep = "$tDim│$tRst"

    # Working dir: last folder only
    $segDir = "$tBlu$(Split-Path -Leaf $cwd)$tRst"

    # Git: branch + ahead/behind (cached refs) + dirty/staged marker
    $segGit = ""
    if ($branch) {
        $segGit = "$tGrn$branch$tRst"
        $up = git -C $cwd rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
        if ($up) {
            $ahead = git -C $cwd rev-list --count "$up..HEAD" 2>$null
            $behind = git -C $cwd rev-list --count "HEAD..$up" 2>$null
            $sync = ""
            if ($ahead -and $ahead -ne "0") { $sync = "↑$ahead" }
            if ($behind -and $behind -ne "0") { if ($sync) { $sync += " " }; $sync += "↓$behind" }
            if ($sync) { $segGit += " $tYel[$sync]$tRst" }
        }
        git -C $cwd --no-optional-locks diff --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            $segGit += " $tRed*$tRst"
        } else {
            git -C $cwd --no-optional-locks diff --cached --quiet 2>$null
            if ($LASTEXITCODE -ne 0) { $segGit += " $tGrn+$tRst" }
        }
    }

    # amq-squad team/session: team = .workstream from nearest .amq-squad/team.json
    $segAmq = ""
    if (Get-Command amq -ErrorAction SilentlyContinue) {
        $amqTeam = ""
        $d = $cwd
        while ($d -and $d -ne [System.IO.Path]::GetPathRoot($d)) {
            $tj = Join-Path $d ".amq-squad" "team.json"
            if (Test-Path $tj) {
                try { $amqTeam = (Get-Content $tj -Raw | ConvertFrom-Json).workstream } catch {}
                break
            }
            $d = Split-Path -Parent $d
        }
        $amqSess = ""
        try { Push-Location $cwd -ErrorAction Stop; $amqSess = amq env --session-name 2>$null; Pop-Location } catch {}
        if (-not $amqSess -and $env:AM_ROOT -and $env:AM_BASE_ROOT -and $env:AM_ROOT -ne $env:AM_BASE_ROOT) {
            $amqSess = Split-Path -Leaf $env:AM_ROOT
        }
        $amqTxt = ""
        if ($amqTeam -and $amqSess -and $amqTeam -ne $amqSess) { $amqTxt = "amq:$amqTeam/$amqSess" }
        elseif ($amqTeam) { $amqTxt = "amq:$amqTeam" }
        elseif ($amqSess) { $amqTxt = "amq:$amqSess" }
        if ($amqTxt -and $env:AM_ME) { $amqTxt += "@$($env:AM_ME)" }
        if ($amqTxt) { $segAmq = "$tYel$amqTxt$tRst" }
    }

    # Model + effort (effort null when the model doesn't support the param)
    $segModel = "$tCyn$model_short$tRst"
    if ($effort) { $segModel += " $tDim$effort$tRst" }

    # Context remaining %, health-colored
    $rem = 100 - $percent
    if ($rem -lt 0) { $rem = 0 }
    $cc = if ($rem -le 20) { $tRed } elseif ($rem -le 40) { $tYel } else { $tGrn }
    $segCtx = "$cc$rem%$tRst"

    # 5h / 7d rate limits, health-colored
    $segRates = ""
    if ($null -ne $rate_5h -and "$rate_5h" -ne "") {
        $r5 = [int][math]::Floor([double]$rate_5h)
        $c5 = if ($r5 -ge 80) { $tRed } elseif ($r5 -ge 50) { $tYel } else { $tGrn }
        $segRates = "${c5}5h:$r5%$tRst"
        if ($null -ne $rate_7d -and "$rate_7d" -ne "") {
            $r7 = [int][math]::Floor([double]$rate_7d)
            $c7 = if ($r7 -ge 80) { $tRed } elseif ($r7 -ge 50) { $tYel } else { $tGrn }
            $segRates += " ${c7}7d:$r7%$tRst"
        }
    }

    # API cost (cents precision; skip $0 and when hidden)
    $segCost = ""
    if (-not $env:CLAUDE_PULSE_HIDE_COST -and $null -ne $cost_usd -and [double]$cost_usd -gt 0) {
        $costStr = ([double]$cost_usd).ToString('0.00')
        $segCost = "${tGrn}`$${costStr}${tRst}"
    }

    # Alert: full text for a real alert; compact the idle daemon line to its glyph
    $segAlert = ""
    if ($alert_segment) {
        $a = $alert_segment -replace "^`n", ""
        if ($a -match 'daemon ON') { $segAlert = "$tGrn🟢$tRst" }
        elseif ($a -match 'not running') { $segAlert = "$tDim🔕$tRst" }
        else { $segAlert = $a }
    }

    $parts = @($segDir, $segGit, $segAmq, $segModel, $segCtx, $segRates, $segCost, $segAlert) | Where-Object { $_ }
    Write-Host ($parts -join " $tSep ")
    exit 0
}

# Output format: "🧠 [████░░] 72% · 🤖 Model · 💬 Topic · 🌿 branch 📁 /path"
Write-Host "${color}🧠 $bar ${percent}%${reset} · 🤖 ${model_name} (${context_label})${name_segment}${pr_segment}${diff_segment} · 📁 ${cwd}${alert_segment}"
