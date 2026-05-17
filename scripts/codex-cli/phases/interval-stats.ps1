# scripts/codex-cli/phases/interval-stats.ps1
# Synchronisiert Datenbank, Registry und GitHub Issues für das Dashboard

Set-StrictMode -Version Latest
$ScriptDir = Join-Path $PSScriptRoot ".."
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\database-manager.ps1")
. (Join-Path $ScriptDir "lib\telemetry-manager.ps1")

$DashboardPublicDir = Join-Path $ScriptDir "dashboard\public"
if (-not (Test-Path $DashboardPublicDir)) { New-Item -ItemType Directory -Path $DashboardPublicDir | Out-Null }

$ConfigPath = Join-Path $ScriptDir "autopilot-config.json"
$Config = if (Test-Path $ConfigPath) { Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$Repository = if ($Config -and -not [string]::IsNullOrWhiteSpace([string]$Config.repository)) { [string]$Config.repository } else { "Vorce-Studios/Vorce" }
$StatePath = Join-Path $ScriptDir "autopilot-state.json"

$lastGhFetch = [datetime]::MinValue
$dashboardSyncIntervalSec = 60
$ghFetchIntervalSec = 300 # Alle 5 Minuten GitHub und PRs abfragen

function Add-SchedulerSnapshot {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config
    )

    $now = Get-Date
    $planMinutes = [int]$Config.wake_intervals.planning_minutes
    $monitoringMinutes = [int]$Config.wake_intervals.monitoring_minutes

    $lastPlanning = $null
    $lastMonitoring = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$State.last_planning_at)) {
            $lastPlanning = [datetimeoffset]::Parse([string]$State.last_planning_at).LocalDateTime
        }
    } catch { }
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$State.last_monitoring_at)) {
            $lastMonitoring = [datetimeoffset]::Parse([string]$State.last_monitoring_at).LocalDateTime
        }
    } catch { }

    if ($null -eq $lastPlanning) { $lastPlanning = $now }
    if ($null -eq $lastMonitoring) { $lastMonitoring = $now }

    $nextPlanning = $lastPlanning.AddMinutes($planMinutes)
    $nextMonitoring = $lastMonitoring.AddMinutes($monitoringMinutes)

    $scheduler = [pscustomobject]@{
        planning_interval_minutes = $planMinutes
        monitoring_interval_minutes = $monitoringMinutes
        last_planning_at = $State.last_planning_at
        last_monitoring_at = $State.last_monitoring_at
        next_planning_at = $nextPlanning.ToString("o")
        next_monitoring_at = $nextMonitoring.ToString("o")
        next_planning_in_seconds = [Math]::Max(0, [int][Math]::Round(($nextPlanning - $now).TotalSeconds))
        next_monitoring_in_seconds = [Math]::Max(0, [int][Math]::Round(($nextMonitoring - $now).TotalSeconds))
        generated_at = $now.ToString("o")
    }

    $State | Add-Member -MemberType NoteProperty -Name "scheduler" -Value $scheduler -Force
    return $State
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " VORCE AUTOPILOT - Persistent Dashboard Sync" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[STATS] Sync Loop gestartet (Ctrl+C zum Beenden)..."

while ($true) {
    try {
        $registry = Read-QuotaRegistry
        $registry = Sync-AutopilotTelemetry -Registry $registry -Config $Config -StatePath $StatePath
        $currentDate = Get-Date -Format "yyyy-MM-dd"
        $reportDate = if (-not [string]::IsNullOrWhiteSpace($registry.last_reset_date)) { $registry.last_reset_date } else { $currentDate }

        # --- DB Sync ---
        foreach ($prop in $registry.providers.PSObject.Properties) {
            $providerName = $prop.Name
            $provider = $prop.Value
            Ensure-ProviderUsageToday -Provider $provider
            Clear-DailyUsageForProvider -Date $reportDate -ProviderName $providerName

            $modelBuckets = @($provider.usage_today.PSObject.Properties | Where-Object {
                $_.Name -notin @("calls", "estimated_cost_usd", "source", "last_synced_at", "rate_limits", "quota_buckets", "quota_source", "quota_synced_at", "quota_error", "active_sessions", "completed_sessions", "failed_sessions", "pending_sessions", "api_sessions_seen", "api_sessions_today", "account_sessions_observed_today", "account_sessions_observed_rolling_24h", "live_capacity_sessions", "live_in_progress_sessions", "live_queued_sessions", "live_waiting_sessions", "scoped_live_capacity_sessions", "scoped_live_in_progress_sessions", "scoped_live_queued_sessions", "scoped_live_waiting_sessions", "last_error") -and
                $null -ne $_.Value -and
                (Test-ObjectProperty -Object $_.Value -Name "calls")
            })

            if ($modelBuckets.Count -eq 0) {
                $totals = Get-ProviderUsageTotals -Provider $provider
                if ([int]$totals.calls -gt 0) {
                    Save-DailyUsage -Date $reportDate -ProviderName $providerName -ModelName "aggregate" -Calls ([int]$totals.calls) -CostUsd ([double]$totals.estimated_cost_usd) -InputTokens 0 -OutputTokens 0 -CachedTokens 0 -ReasoningTokens 0 -ToolTokens 0 -DurationMs 0
                }
            }

            foreach ($modelProp in $modelBuckets) {
                $modelName = $modelProp.Name
                $modUsage = $modelProp.Value
                $calls = [int]($modUsage.calls)
                if ($calls -gt 0) {
                    $cost = [double]($modUsage.estimated_cost_usd)
                    $inputTokens = if ($modUsage.PSObject.Properties.Name -contains "total_input_tokens" -and $modUsage.total_input_tokens) { [int]$modUsage.total_input_tokens } else { 0 }
                    $outputTokens = if ($modUsage.PSObject.Properties.Name -contains "total_output_tokens" -and $modUsage.total_output_tokens) { [int]$modUsage.total_output_tokens } else { 0 }
                    $cachedTokens = if ($modUsage.PSObject.Properties.Name -contains "cached_tokens" -and $modUsage.cached_tokens) { [int]$modUsage.cached_tokens } else { 0 }
                    $reasoningTokens = if ($modUsage.PSObject.Properties.Name -contains "reasoning_tokens" -and $modUsage.reasoning_tokens) { [int]$modUsage.reasoning_tokens } else { 0 }
                    $toolTokens = if ($modUsage.PSObject.Properties.Name -contains "tool_tokens" -and $modUsage.tool_tokens) { [int]$modUsage.tool_tokens } else { 0 }
                    $durationMs = if ($modUsage.PSObject.Properties.Name -contains "total_duration_ms" -and $modUsage.total_duration_ms) { [int]$modUsage.total_duration_ms } else { 0 }

                    Save-DailyUsage -Date $reportDate -ProviderName $providerName -ModelName $modelName -Calls $calls -CostUsd $cost -InputTokens $inputTokens -OutputTokens $outputTokens -CachedTokens $cachedTokens -ReasoningTokens $reasoningTokens -ToolTokens $toolTokens -DurationMs $durationMs
                }
            }
        }

        # --- File Export ---
        $DbPath = Join-Path $ScriptDir "historical-quota-db.json"
        if (Test-Path $DbPath) {
            $db = Read-JsonLocked -Path $DbPath
            if ($null -eq $db) { $db = @() }
            Write-JsonLocked -Path (Join-Path $DashboardPublicDir "data.json") -Data @($db) | Out-Null
        }

        if (Test-Path $StatePath) {
            $state = Read-JsonLocked -Path $StatePath
            if ($null -ne $state) {
                $state = Add-SchedulerSnapshot -State $state -Config $Config
                Write-JsonLocked -Path (Join-Path $DashboardPublicDir "active-sessions.json") -Data $state | Out-Null
            }
        }

        $RegistryPath = Join-Path $ScriptDir "quota-registry.json"
        if (Test-Path $RegistryPath) {
            Write-JsonLocked -Path (Join-Path $DashboardPublicDir "registry.json") -Data $registry | Out-Null
        }

        # --- GitHub / PR Polling (Throttled) ---
        $now = Get-Date
        if (($now - $lastGhFetch).TotalSeconds -ge $ghFetchIntervalSec) {
            Write-Host "[STATS] Polling GitHub Issues..." -ForegroundColor Gray
            $issuesRaw = gh issue list --repo $Repository --state all --limit 1000 --json number,title,state,url,updatedAt,createdAt,labels,body,assignees,milestone 2>$null
            if ($LASTEXITCODE -eq 0) {
                $issueJson = $issuesRaw | Out-String
                $issueData = $issueJson | ConvertFrom-Json -ErrorAction Stop
                Write-JsonLocked -Path (Join-Path $DashboardPublicDir "github-issues.json") -Data @($issueData) | Out-Null
                Write-Host "[STATS] GitHub Issues updated." -ForegroundColor Gray
            }

            $prsRaw = gh pr list --repo $Repository --state open --limit 1000 --json number,title,state,url,updatedAt,headRefName,baseRefName,mergeable,statusCheckRollup 2>$null
            if ($LASTEXITCODE -eq 0) {
                $prJson = $prsRaw | Out-String
                $prData = $prJson | ConvertFrom-Json -ErrorAction Stop
                Write-JsonLocked -Path (Join-Path $DashboardPublicDir "pull-requests.json") -Data @($prData) | Out-Null
                Write-Host "[STATS] Pull Requests updated." -ForegroundColor Gray
            }

            $lastGhFetch = $now
        }

    } catch {
        Write-Warning "[STATS] Sync Fehler: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $dashboardSyncIntervalSec
}
