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
$ghFetchIntervalSec = 300 # Alle 5 Minuten GitHub abfragen

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
                $_.Name -notin @("calls", "estimated_cost_usd", "source", "last_synced_at", "rate_limits", "active_sessions", "completed_sessions", "failed_sessions", "pending_sessions", "api_sessions_seen", "last_error") -and
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
            if ($null -ne $state) { Write-JsonLocked -Path (Join-Path $DashboardPublicDir "active-sessions.json") -Data $state | Out-Null }
        }
        
        $RegistryPath = Join-Path $ScriptDir "quota-registry.json"
        if (Test-Path $RegistryPath) {
            Write-JsonLocked -Path (Join-Path $DashboardPublicDir "registry.json") -Data $registry | Out-Null
        }

        # --- GitHub Polling (Throttled) ---
        $now = Get-Date
        if (($now - $lastGhFetch).TotalSeconds -ge $ghFetchIntervalSec) {
            Write-Host "[STATS] Polling GitHub Issues..." -ForegroundColor Gray
            $issuesRaw = gh issue list --repo $Repository --state all --limit 100 --json number,title,state,url,updatedAt,labels,body 2>$null
            if ($LASTEXITCODE -eq 0) {
                $issueJson = $issuesRaw | Out-String
                $issueData = $issueJson | ConvertFrom-Json -ErrorAction Stop
                Write-JsonLocked -Path (Join-Path $DashboardPublicDir "github-issues.json") -Data @($issueData) | Out-Null
                $lastGhFetch = $now
                Write-Host "[STATS] GitHub Issues updated." -ForegroundColor Gray
            }
        }

    } catch {
        Write-Warning "[STATS] Sync Fehler: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 15
}
