# Vorce-Autopilot/src/lib/telemetry-manager.ps1
# Collects local CLI telemetry and Jules API session snapshots for quota reporting.

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "quota-manager.ps1")

$script:ScriptRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$script:RepoRoot = Resolve-Path (Join-Path $script:ScriptRoot "..")
$script:VarDbDir = Join-Path $script:ScriptRoot "var/db"

$script:TelemetryStatePath = Join-Path $script:VarDbDir "telemetry-state.json"
$script:JulesApiPath = Join-Path $script:RepoRoot "scripts/jules/jules-api.ps1"
$script:GeminiQuotaHelperPath = Join-Path $script:ScriptRoot "tools\gemini-quota.mjs"

# Ensure var/db exists
if (-not (Test-Path -Path $script:VarDbDir)) {
    New-Item -ItemType Directory -Path $script:VarDbDir -Force | Out-Null
}

if (Test-Path $script:JulesApiPath) {
    . $script:JulesApiPath
}

function New-TelemetryUsage {
    return [pscustomobject]@{
        calls = 0
        estimated_cost_usd = 0.0
        source = "telemetry"
        last_synced_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function Get-TelemetryNumber {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return [int64]0 }
    try { return [int64]$Value } catch { return [int64]0 }
}

function Get-TelemetryDouble {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 0.0 }
    try { return [double]$Value } catch { return 0.0 }
}

function Convert-TelemetryResetToEpochSeconds {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }

    try {
        $numeric = [double]$Value
        if ($numeric -gt 0) { return [int64][Math]::Round($numeric) }
    } catch {
        # Fall through and try ISO/date parsing.
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.ToUnixTimeSeconds()
    } catch {
        return $null
    }
}

function Convert-TelemetryTimestampToIsoString {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return (Get-Date).ToUniversalTime().ToString("o")
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString("o")
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.UtcDateTime.ToString("o")
    } catch {
        return [string]$Value
    }
}

function Get-TelemetryPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Test-TelemetryTimestampMatchesDate {
    param(
        [AllowNull()][object]$Timestamp,
        [Parameter(Mandatory)][string]$Date
    )

    if ($null -eq $Timestamp -or [string]::IsNullOrWhiteSpace([string]$Timestamp)) {
        return $false
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.UtcDateTime.ToString("yyyy-MM-dd") -eq $Date
    } catch {
        return $false
    }
}

function Test-TelemetryTimestampMatchesDateLocalOrUtc {
    param(
        [AllowNull()][object]$Timestamp,
        [Parameter(Mandatory)][string]$Date
    )

    if ($null -eq $Timestamp -or [string]::IsNullOrWhiteSpace([string]$Timestamp)) {
        return $false
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.UtcDateTime.ToString("yyyy-MM-dd") -eq $Date -or $dto.LocalDateTime.ToString("yyyy-MM-dd") -eq $Date
    } catch {
        return $false
    }
}

function Get-TelemetryReportRange {
    param([Parameter(Mandatory)][string]$Date)

    try {
        $start = [datetime]::SpecifyKind(
            [datetime]::ParseExact($Date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture),
            [System.DateTimeKind]::Utc
        )
    } catch {
        $start = [datetime]::UtcNow.Date
    }

    return [pscustomobject]@{
        Start = $start
        End = $start.AddDays(1)
    }
}

function Get-TelemetrySessionDirectories {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][datetime]$Now
    )

    if (-not (Test-Path $Root)) { return @() }

    $dates = @(
        $Now.ToUniversalTime().AddDays(-1),
        $Now.ToUniversalTime(),
        $Now.ToUniversalTime().AddDays(1),
        $Now.AddDays(-1),
        $Now,
        $Now.AddDays(1)
    )

    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($date in $dates) {
        $path = Join-Path $Root ($date.ToString("yyyy\\MM\\dd"))
        if (Test-Path $path) {
            [void]$paths.Add([System.IO.Path]::GetFullPath($path))
        }
    }

    return @($paths)
}

function Read-TelemetryJsonlLines {
    param([Parameter(Mandatory)][string]$Path)

    $lines = [System.Collections.Generic.List[string]]::new()
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        while (-not $reader.EndOfStream) {
            [void]$lines.Add($reader.ReadLine())
        }
    } catch {
        return @()
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }

    return @($lines)
}

function Add-TelemetryUsage {
    param(
        [Parameter(Mandatory)][object]$Usage,
        [Parameter(Mandatory)][string]$ModelName,
        [int64]$Calls = 1,
        [int64]$InputTokens = 0,
        [int64]$OutputTokens = 0,
        [int64]$CachedTokens = 0,
        [int64]$ReasoningTokens = 0,
        [int64]$ToolTokens = 0,
        [int64]$DurationMs = 0,
        [double]$CostUsd = 0.0
    )

    $safeModelName = if ([string]::IsNullOrWhiteSpace($ModelName)) { "unknown" } else { $ModelName }

    if (-not (Test-ObjectProperty -Object $Usage -Name $safeModelName) -or $null -eq $Usage.$safeModelName) {
        $Usage | Add-Member -MemberType NoteProperty -Name $safeModelName -Value ([pscustomobject]@{
            calls = 0
            estimated_cost_usd = 0.0
            total_input_tokens = 0
            total_output_tokens = 0
            cached_tokens = 0
            reasoning_tokens = 0
            tool_tokens = 0
            total_duration_ms = 0
        }) -Force
    }

    $bucket = $Usage.$safeModelName
    $bucket.calls = [int64]$bucket.calls + $Calls
    $bucket.estimated_cost_usd = [Math]::Round([double]$bucket.estimated_cost_usd + $CostUsd, 6)
    $bucket.total_input_tokens = [int64]$bucket.total_input_tokens + $InputTokens
    $bucket.total_output_tokens = [int64]$bucket.total_output_tokens + $OutputTokens
    $bucket.cached_tokens = [int64]$bucket.cached_tokens + $CachedTokens
    $bucket.reasoning_tokens = [int64]$bucket.reasoning_tokens + $ReasoningTokens
    $bucket.tool_tokens = [int64]$bucket.tool_tokens + $ToolTokens
    $bucket.total_duration_ms = [int64]$bucket.total_duration_ms + $DurationMs

    $Usage.calls = [int64]$Usage.calls + $Calls
    $Usage.estimated_cost_usd = [Math]::Round([double]$Usage.estimated_cost_usd + $CostUsd, 6)
}

function Get-ModelCostPerCall {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][string]$ModelName
    )

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return 0.0 }

    if ((Test-ObjectProperty -Object $provider -Name "models") -and $provider.models) {
        foreach ($modelProp in $provider.models.PSObject.Properties) {
            $configuredName = [string](Get-TelemetryPropertyValue -Object $modelProp.Value -Name "name")
            if ($configuredName -eq $ModelName) {
                return Get-TelemetryDouble (Get-TelemetryPropertyValue -Object $modelProp.Value -Name "estimated_cost_per_call_usd")
            }
        }
    }

    if (Test-ObjectProperty -Object $provider -Name "estimated_cost_per_call_usd") {
        return Get-TelemetryDouble $provider.estimated_cost_per_call_usd
    }

    return 0.0
}

function Get-CodexTelemetryUsage {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ReportDate
    )

    $usage = New-TelemetryUsage
    $usage.source = "codex-local-jsonl"
    $root = Join-Path $HOME ".codex/sessions"
    $dirs = Get-TelemetrySessionDirectories -Root $root -Now (Get-Date)

    foreach ($dir in $dirs) {
        foreach ($file in @(Get-ChildItem -Path $dir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue)) {
            $currentModel = "codex"
            $lineNumber = 0
            foreach ($line in (Read-TelemetryJsonlLines -Path $file.FullName)) {
                $lineNumber++
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                $eventType = [string](Get-TelemetryPropertyValue -Object $event -Name "type")
                $payload = Get-TelemetryPropertyValue -Object $event -Name "payload"
                $payloadType = [string](Get-TelemetryPropertyValue -Object $payload -Name "type")

                if ($eventType -eq "session_meta") {
                    foreach ($field in @("model", "model_slug", "modelProvider", "model_provider")) {
                        $modelCandidate = [string](Get-TelemetryPropertyValue -Object $payload -Name $field)
                        if (-not [string]::IsNullOrWhiteSpace($modelCandidate) -and $modelCandidate -ne "openai") {
                            $currentModel = $modelCandidate
                            break
                        }
                    }
                    continue
                }

                if ($payloadType -eq "task_started") {
                    foreach ($field in @("model", "model_slug")) {
                        $modelCandidate = [string](Get-TelemetryPropertyValue -Object $payload -Name $field)
                        if (-not [string]::IsNullOrWhiteSpace($modelCandidate)) {
                            $currentModel = $modelCandidate
                            break
                        }
                    }
                    continue
                }

                if ($payloadType -ne "token_count" -and $eventType -ne "token_count") { continue }
                if (-not (Test-TelemetryTimestampMatchesDateLocalOrUtc -Timestamp (Get-TelemetryPropertyValue -Object $event -Name "timestamp") -Date $ReportDate)) {
                    continue
                }

                $tokenEvent = if ($payloadType -eq "token_count") { $payload } else { $event }
                $info = Get-TelemetryPropertyValue -Object $tokenEvent -Name "info"
                $tokenUsage = Get-TelemetryPropertyValue -Object $info -Name "last_token_usage"
                if ($null -eq $tokenUsage) {
                    $tokenUsage = Get-TelemetryPropertyValue -Object $info -Name "total_token_usage"
                }
                if ($null -eq $tokenUsage) { continue }

                $modelName = $currentModel
                $cost = Get-ModelCostPerCall -Registry $Registry -ProviderName "codex_orchestrator" -ModelName $modelName
                Add-TelemetryUsage -Usage $usage -ModelName $modelName -Calls 1 `
                    -InputTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "input_tokens")) `
                    -OutputTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "output_tokens")) `
                    -CachedTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "cached_input_tokens")) `
                    -ReasoningTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokenUsage -Name "reasoning_output_tokens")) `
                    -CostUsd $cost

                $rateLimits = Get-TelemetryPropertyValue -Object $tokenEvent -Name "rate_limits"
                if ($null -ne $rateLimits) {
                    $usage | Add-Member -MemberType NoteProperty -Name "rate_limits" -Value $rateLimits -Force
                }
            }
        }
    }

    return $usage
}

function Get-GeminiCliQuotaSnapshot {
    param([AllowNull()][object]$Config)

    if (-not (Test-Path $script:GeminiQuotaHelperPath)) {
        return [pscustomobject]@{
            ok = $false
            source = "gemini-cli-retrieveUserQuota"
            error = "Gemini quota helper not found: $script:GeminiQuotaHelperPath"
        }
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $node) {
        return [pscustomobject]@{
            ok = $false
            source = "gemini-cli-retrieveUserQuota"
            error = "node executable not found"
        }
    }

    $repoRoot = $script:RepoRoot
    if ($Config -and (Test-ObjectProperty -Object $Config -Name "gemini_worktree_path") -and -not [string]::IsNullOrWhiteSpace([string]$Config.gemini_worktree_path)) {
        try {
            $configuredPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$Config.gemini_worktree_path)))
            if (Test-Path $configuredPath) { $repoRoot = $configuredPath }
        } catch {
            # Invalid optional config path
        }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = [string]$node.Source
    $psi.Arguments = "`"$script:GeminiQuotaHelperPath`" --cwd `"$repoRoot`""
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    try {
        [void]$process.Start()
        if (-not $process.WaitForExit(45000)) {
            try { $process.Kill() } catch { }
            return [pscustomobject]@{
                ok = $false
                source = "gemini-cli-retrieveUserQuota"
                error = "Gemini quota helper timed out after 45s"
            }
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($stdout)) {
            return [pscustomobject]@{
                ok = $false
                source = "gemini-cli-retrieveUserQuota"
                error = $(if ([string]::IsNullOrWhiteSpace($stderr)) { "Gemini quota helper returned no output" } else { $stderr.Trim() })
            }
        }

        $jsonLine = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
        return ($jsonLine | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return [pscustomobject]@{
            ok = $false
            source = "gemini-cli-retrieveUserQuota"
            error = $_.Exception.Message
        }
    } finally {
        if ($null -ne $process) { $process.Dispose() }
    }
}

function Add-GeminiCliQuotaToUsage {
    param(
        [Parameter(Mandatory)][object]$Usage,
        [AllowNull()][object]$QuotaSnapshot
    )

    if ($null -eq $QuotaSnapshot) { return }

    $Usage | Add-Member -MemberType NoteProperty -Name "quota_source" -Value ([string](Get-TelemetryPropertyValue -Object $QuotaSnapshot -Name "source")) -Force
    $Usage | Add-Member -MemberType NoteProperty -Name "quota_synced_at" -Value (Convert-TelemetryTimestampToIsoString (Get-TelemetryPropertyValue -Object $QuotaSnapshot -Name "fetched_at")) -Force

    $isOk = $false
    try { $isOk = [bool](Get-TelemetryPropertyValue -Object $QuotaSnapshot -Name "ok") } catch { $isOk = $false }
    if (-not $isOk) {
        $errorMessage = [string](Get-TelemetryPropertyValue -Object $QuotaSnapshot -Name "error")
        if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
            $Usage | Add-Member -MemberType NoteProperty -Name "quota_error" -Value $errorMessage -Force
        }
        return
    }

    $pooled = Get-TelemetryPropertyValue -Object $QuotaSnapshot -Name "pooled"
    if ($null -eq $pooled) { return }

    $remaining = Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $pooled -Name "remaining")
    $limit = Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $pooled -Name "limit")
    $usedPercent = Get-TelemetryDouble (Get-TelemetryPropertyValue -Object $pooled -Name "used_percent")
    $resetEpoch = Convert-TelemetryResetToEpochSeconds (Get-TelemetryPropertyValue -Object $pooled -Name "resets_at")

    $primary = [pscustomobject]@{
        label = "Gemini quota"
        used_percent = $usedPercent
        remaining = $remaining
        limit = $limit
        resets_at = $resetEpoch
        source = "gemini-cli"
    }

    $buckets = @()
    $rawBuckets = Get-TelemetryPropertyValue -Object $QuotaSnapshot -Name "buckets"
    if ($null -ne $rawBuckets) {
        foreach ($bucket in @($rawBuckets)) {
            $buckets += [pscustomobject]@{
                model_id = [string](Get-TelemetryPropertyValue -Object $bucket -Name "model_id")
                used_percent = Get-TelemetryDouble (Get-TelemetryPropertyValue -Object $bucket -Name "used_percent")
                remaining = Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $bucket -Name "remaining")
                limit = Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $bucket -Name "limit")
                resets_at = Convert-TelemetryResetToEpochSeconds (Get-TelemetryPropertyValue -Object $bucket -Name "resets_at")
            }
        }
    }

    $secondary = $null
    $mostConstrained = @($buckets | Sort-Object -Property used_percent -Descending | Select-Object -First 1)
    if ($mostConstrained.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$mostConstrained[0].model_id)) {
        $secondary = [pscustomobject]@{
            label = "Max model bucket"
            used_percent = [double]$mostConstrained[0].used_percent
            remaining = [int64]$mostConstrained[0].remaining
            limit = [int64]$mostConstrained[0].limit
            resets_at = $mostConstrained[0].resets_at
            model_id = [string]$mostConstrained[0].model_id
            source = "gemini-cli"
        }
    }

    $rateLimits = [pscustomobject]@{
        limit_id = "gemini-cli"
        limit_name = "Gemini CLI quota"
        primary = $primary
        secondary = $secondary
        buckets = $buckets
        plan_type = $null
        rate_limit_reached_type = $null
    }

    $Usage | Add-Member -MemberType NoteProperty -Name "rate_limits" -Value $rateLimits -Force
    $Usage | Add-Member -MemberType NoteProperty -Name "quota_buckets" -Value $buckets -Force
    $Usage.source = "gemini-local-jsonl+cli-quota"
}

function Get-GeminiTelemetryUsage {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ReportDate,
        [AllowNull()][object]$Config
    )

    $usage = New-TelemetryUsage
    $usage.source = "gemini-local-jsonl"
    Add-GeminiCliQuotaToUsage -Usage $usage -QuotaSnapshot (Get-GeminiCliQuotaSnapshot -Config $Config)
    $root = Join-Path $HOME ".gemini\tmp"
    if (-not (Test-Path $root)) { return $usage }

    $range = Get-TelemetryReportRange -Date $ReportDate
    $seenMessages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $roots = [System.Collections.Generic.List[string]]::new()
    $repoRoot = $script:RepoRoot
    $repoLeaf = (Split-Path $repoRoot -Leaf).ToLowerInvariant()
    foreach ($name in @($repoLeaf, "$repoLeaf-1")) {
        $candidateRoot = Join-Path $root $name
        if (Test-Path $candidateRoot) { [void]$roots.Add($candidateRoot) }
    }

    if ($Config -and (Test-ObjectProperty -Object $Config -Name "gemini_worktree_path")) {
        try {
            $configuredPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$Config.gemini_worktree_path)))
            $configuredLeaf = (Split-Path $configuredPath -Leaf).ToLowerInvariant()
            foreach ($name in @($configuredLeaf, "$configuredLeaf-1")) {
                $candidateRoot = Join-Path $root $name
                if (Test-Path $candidateRoot) { [void]$roots.Add($candidateRoot) }
            }
        } catch {
            # Ignore invalid optional config paths
        }
    }

    $scanRoots = @($roots | Select-Object -Unique)
    if ($scanRoots.Count -eq 0) { $scanRoots = @($root) }

    $candidateFiles = @()
    foreach ($scanRoot in $scanRoots) {
        $candidateFiles += @(Get-ChildItem -Path $scanRoot -Recurse -Filter "*.jsonl" -File -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTimeUtc -ge $range.Start.AddHours(-2) -and $_.LastWriteTimeUtc -lt $range.End.AddHours(2)
        })
    }

    foreach ($file in $candidateFiles) {
        $lineNumber = 0
        foreach ($line in (Read-TelemetryJsonlLines -Path $file.FullName)) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ([string](Get-TelemetryPropertyValue -Object $event -Name "type") -ne "gemini") { continue }
            if (-not (Test-TelemetryTimestampMatchesDate -Timestamp (Get-TelemetryPropertyValue -Object $event -Name "timestamp") -Date $ReportDate)) {
                continue
            }

            $tokens = Get-TelemetryPropertyValue -Object $event -Name "tokens"
            if ($null -eq $tokens) { continue }

            $messageId = [string](Get-TelemetryPropertyValue -Object $event -Name "id")
            if ([string]::IsNullOrWhiteSpace($messageId)) {
                $messageId = "$($file.FullName):$lineNumber"
            } else {
                $messageId = "$($file.FullName):$messageId"
            }
            if (-not $seenMessages.Add($messageId)) { continue }

            $modelName = [string](Get-TelemetryPropertyValue -Object $event -Name "model")
            if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = "gemini" }
            $cost = Get-ModelCostPerCall -Registry $Registry -ProviderName "gemini_cli" -ModelName $modelName

            Add-TelemetryUsage -Usage $usage -ModelName $modelName -Calls 1 `
                -InputTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokens -Name "input")) `
                -OutputTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokens -Name "output")) `
                -CachedTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokens -Name "cached")) `
                -ReasoningTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokens -Name "thoughts")) `
                -ToolTokens (Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $tokens -Name "tool")) `
                -CostUsd $cost
        }
    }

    return $usage
}

function Read-TelemetryState {
    $state = Read-JsonLocked -Path $script:TelemetryStatePath
    if ($null -eq $state) {
        return [pscustomobject]@{}
    }
    return $state
}

function Write-TelemetryState {
    param([Parameter(Mandatory)][object]$State)
    Write-JsonLocked -Path $script:TelemetryStatePath -Data $State | Out-Null
}

function Test-ShouldPollJulesTelemetry {
    param(
        [Parameter(Mandatory)][object]$State,
        [int]$IntervalSeconds = 300
    )

    $lastPoll = [string](Get-TelemetryPropertyValue -Object $State -Name "jules_last_poll_at")
    if ([string]::IsNullOrWhiteSpace($lastPoll)) { return $true }

    try {
        $last = [datetimeoffset]::Parse($lastPoll, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return ((Get-Date).ToUniversalTime() - $last.UtcDateTime).TotalSeconds -ge $IntervalSeconds
    } catch {
        return $true
    }
}

function Get-JulesSessionTimestamp {
    param([AllowNull()][object]$Session)

    foreach ($field in @("createTime", "createdAt", "startTime", "updateTime", "updatedAt")) {
        $value = Get-TelemetryPropertyValue -Object $Session -Name $field
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return $value
        }
    }

    return $null
}

function Get-JulesSessionSourceName {
    param([AllowNull()][object]$Session)

    $sourceContext = Get-TelemetryPropertyValue -Object $Session -Name "sourceContext"
    return [string](Get-TelemetryPropertyValue -Object $sourceContext -Name "source")
}

function Test-JulesSessionCreatedOnReportDate {
    param(
        [AllowNull()][object]$Session,
        [Parameter(Mandatory)][string]$ReportDate
    )

    $timestampFields = @("createTime", "createdAt", "startTime", "startedAt")
    $hasTimestamp = $false

    foreach ($field in $timestampFields) {
        $value = Get-TelemetryPropertyValue -Object $Session -Name $field
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { continue }
        $hasTimestamp = $true
        if (Test-TelemetryTimestampMatchesDateLocalOrUtc -Timestamp $value -Date $ReportDate) {
            return $true
        }
    }

    return $false
}

function Get-JulesTelemetryUsage {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ReportDate,
        [AllowNull()][object]$Config,
        [string]$StatePath
    )

    $usage = New-TelemetryUsage
    $usage.source = "jules-api"
    $usage | Add-Member -MemberType NoteProperty -Name "active_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "completed_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "failed_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "pending_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_capacity_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_in_progress_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_queued_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_waiting_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "account_sessions_observed_today" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "account_sessions_observed_rolling_24h" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_capacity_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_in_progress_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_queued_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_waiting_sessions" -Value 0 -Force

    $state = if (-not [string]::IsNullOrWhiteSpace($StatePath) -and (Test-Path $StatePath)) { Read-JsonLocked -Path $StatePath } else { $null }

    try {
        if (-not (Get-Command Get-AllJulesSessions -ErrorAction SilentlyContinue)) {
            throw "Jules API helper not loaded."
        }

        $pageSize = 50
        $maxPages = 10
        if ($Config -and (Test-ObjectProperty -Object $Config -Name "jules")) {
            $configuredMaxPages = Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $Config.jules -Name "session_poll_max_pages")
            if ($configuredMaxPages -gt 0) {
                $maxPages = [int]$configuredMaxPages
            }
        }

        $sessions = @(Get-AllJulesSessions -PageSize $pageSize -MaxPages $maxPages)
        $usage | Add-Member -MemberType NoteProperty -Name "api_sessions_seen" -Value $sessions.Count -Force
        $usage | Add-Member -MemberType NoteProperty -Name "api_sessions_today" -Value 0 -Force

        $scopedSources = @()
        if ($Config -and (Test-ObjectProperty -Object $Config -Name "repository") -and -not [string]::IsNullOrWhiteSpace([string]$Config.repository)) {
            $primaryRepo = [string]$Config.repository
            $scopedSources += "sources/github/$primaryRepo"
            if ($primaryRepo -eq "Vorce-Studios/Vorce") {
                $scopedSources += "sources/github/MrLongNight/MapFlow"
            }
        }
        $now = [datetimeoffset]::Now

        foreach ($session in $sessions) {
            $stateName = [string](Get-TelemetryPropertyValue -Object $session -Name "state")
            if ([string]::IsNullOrWhiteSpace($stateName)) { $stateName = "UNKNOWN" }
            $sessionSource = Get-JulesSessionSourceName -Session $session
            $isScoped = $scopedSources.Count -gt 0 -and $sessionSource -in $scopedSources

            switch -Regex ($stateName) {
                "^IN_PROGRESS$" { $usage.live_in_progress_sessions = [int64]$usage.live_in_progress_sessions + 1; $usage.live_capacity_sessions = [int64]$usage.live_capacity_sessions + 1; break }
                "^QUEUED$|^PLANNING$|^AWAITING_PLAN_APPROVAL$" { $usage.live_queued_sessions = [int64]$usage.live_queued_sessions + 1; $usage.live_capacity_sessions = [int64]$usage.live_capacity_sessions + 1; break }
                "^AWAITING_USER_FEEDBACK$|^PAUSED$" { $usage.live_waiting_sessions = [int64]$usage.live_waiting_sessions + 1; break }
            }

            if ($isScoped) {
                switch -Regex ($stateName) {
                    "^IN_PROGRESS$" { $usage.scoped_live_in_progress_sessions = [int64]$usage.scoped_live_in_progress_sessions + 1; $usage.scoped_live_capacity_sessions = [int64]$usage.scoped_live_capacity_sessions + 1; break }
                    "^QUEUED$|^PLANNING$|^AWAITING_PLAN_APPROVAL$" { $usage.scoped_live_queued_sessions = [int64]$usage.scoped_live_queued_sessions + 1; $usage.scoped_live_capacity_sessions = [int64]$usage.scoped_live_capacity_sessions + 1; break }
                    "^AWAITING_USER_FEEDBACK$|^PAUSED$" { $usage.scoped_live_waiting_sessions = [int64]$usage.scoped_live_waiting_sessions + 1; break }
                }
            }

            try {
                $createdAt = [datetimeoffset]::Parse([string](Get-TelemetryPropertyValue -Object $session -Name "createTime"))
                if (($now - $createdAt.ToLocalTime()) -lt [timespan]::FromHours(24)) {
                    $usage.account_sessions_observed_rolling_24h = [int64]$usage.account_sessions_observed_rolling_24h + 1
                }
            } catch { }

            if (-not (Test-JulesSessionCreatedOnReportDate -Session $session -ReportDate $ReportDate)) {
                continue
            }
            $usage.account_sessions_observed_today = [int64]$usage.account_sessions_observed_today + 1
            $usage.api_sessions_today = [int64]$usage.api_sessions_today + 1

            switch -Regex ($stateName) {
                "FAILED|ERROR|CANCEL" { $usage.failed_sessions = [int64]$usage.failed_sessions + 1; break }
                "COMPLETE|MERGED|DONE" { $usage.completed_sessions = [int64]$usage.completed_sessions + 1; break }
            }

            Add-TelemetryUsage -Usage $usage -ModelName "sessions" -Calls 1
        }
        $usage.active_sessions = [int64]$usage.scoped_live_capacity_sessions
        $usage.pending_sessions = [int64]$usage.scoped_live_waiting_sessions
    } catch {
        $usage.source = "jules-api-fallback"
        $usage | Add-Member -MemberType NoteProperty -Name "last_error" -Value $_.Exception.Message -Force

        if ($null -ne $state -and (Test-ObjectProperty -Object $state -Name "active_delegations")) {
            foreach ($delegation in @($state.active_delegations)) {
                Add-TelemetryUsage -Usage $usage -ModelName "sessions" -Calls 1
                $usage.active_sessions = [int64]$usage.active_sessions + 1
            }
        }
    }

    return $usage
}

function Sync-AutopilotTelemetry {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [AllowNull()][object]$Config,
        [string]$StatePath
    )

    $reportDate = if (-not [string]::IsNullOrWhiteSpace([string]$Registry.last_reset_date)) {
        [string]$Registry.last_reset_date
    } else {
        (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    }

    $codexUsage = Get-CodexTelemetryUsage -Registry $Registry -ReportDate $reportDate
    Set-ProviderUsageSnapshot -Registry $Registry -ProviderName "codex_orchestrator" -UsageToday $codexUsage

    $geminiUsage = Get-GeminiTelemetryUsage -Registry $Registry -ReportDate $reportDate -Config $Config
    Set-ProviderUsageSnapshot -Registry $Registry -ProviderName "gemini_cli" -UsageToday $geminiUsage

    $telemetryState = Read-TelemetryState
    if (Test-ShouldPollJulesTelemetry -State $telemetryState -IntervalSeconds 300) {
        $julesUsage = Get-JulesTelemetryUsage -Registry $Registry -ReportDate $reportDate -Config $Config -StatePath $StatePath
        Set-ProviderUsageSnapshot -Registry $Registry -ProviderName "jules" -UsageToday $julesUsage
        $telemetryState | Add-Member -MemberType NoteProperty -Name "jules_last_poll_at" -Value (Get-Date).ToUniversalTime().ToString("o") -Force
        $telemetryState | Add-Member -MemberType NoteProperty -Name "jules_last_source" -Value $julesUsage.source -Force
        if (Test-ObjectProperty -Object $julesUsage -Name "last_error") {
            $telemetryState | Add-Member -MemberType NoteProperty -Name "jules_last_error" -Value $julesUsage.last_error -Force
        }
        Write-TelemetryState -State $telemetryState
    }

    return (Read-QuotaRegistry)
}
