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

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
    if ($Config -and (Test-ObjectProperty -Object $Config -Name "gemini_worktree_path") -and -not [string]::IsNullOrWhiteSpace([string]$Config.gemini_worktree_path)) {
        try {
            $configuredPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$Config.gemini_worktree_path)))
            if (Test-Path $configuredPath) { $repoRoot = $configuredPath }
        } catch {
            # Invalid optional config path; use repository root.
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
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
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
            # Ignore invalid optional config paths and fall back to discovered roots.
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
