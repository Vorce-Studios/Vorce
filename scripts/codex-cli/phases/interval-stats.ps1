# scripts/codex-cli/phases/interval-stats.ps1
# Runs periodically to sync current quota registry to the historical database

Set-StrictMode -Version Latest

$ScriptDir = Join-Path $PSScriptRoot ".."
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\database-manager.ps1")

Write-Host "====================================="
Write-Host " VORCE AUTOPILOT - Interval Stats Sync"
Write-Host "====================================="

$registry = Read-QuotaRegistry
$currentDate = Get-Date -Format "yyyy-MM-dd"

# Ensure registry has today's date if last_reset_date is empty, otherwise use last_reset_date
$reportDate = if (-not [string]::IsNullOrWhiteSpace($registry.last_reset_date)) { $registry.last_reset_date } else { $currentDate }

Write-Host "[STATS] Syncing usage for date: $reportDate" -ForegroundColor Cyan

$syncedProviders = 0

foreach ($prop in $registry.providers.PSObject.Properties) {
    $providerName = $prop.Name
    $provider = $prop.Value

    $hasData = $false
    foreach ($modelProp in $provider.usage_today.PSObject.Properties) {
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
            $hasData = $true
        }
    }
    
    if ($hasData) {
        $syncedProviders++
    }
}

if ($syncedProviders -eq 0) {
    Write-Host "[STATS] No usage recorded today. Nothing to sync." -ForegroundColor DarkGray
} else {
    Write-Host "[STATS] Successfully synced $syncedProviders providers to historical DB." -ForegroundColor Green
}

# Provide an overview of the total DB
[array]$db = Read-Database
$totalCalls = 0
$totalCost = 0.0

foreach ($entry in $db) {
    $totalCalls += $entry.calls
    $totalCost += $entry.cost_usd
}

Write-Host ""
Write-Host "--- Historical DB Overview ---"
Write-Host "Total Recorded Days/Providers: $($db.Count)"
Write-Host "Total Historical Calls:        $totalCalls"
Write-Host ("Total Historical Cost:         `${0}" -f [Math]::Round($totalCost, 4))
Write-Host "====================================="

# Export Data to Dashboard
$DashboardPublicDir = Join-Path $ScriptDir "dashboard\public"
if (-not (Test-Path $DashboardPublicDir)) { New-Item -ItemType Directory -Path $DashboardPublicDir | Out-Null }

$DbPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "historical-quota-db.json"))
if (Test-Path $DbPath) {
    Copy-Item $DbPath -Destination (Join-Path $DashboardPublicDir "data.json") -Force
}

$StatePath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "autopilot-state.json"))
if (Test-Path $StatePath) {
    Copy-Item $StatePath -Destination (Join-Path $DashboardPublicDir "active-sessions.json") -Force
}

$RegistryPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "quota-registry.json"))
if (Test-Path $RegistryPath) {
    Copy-Item $RegistryPath -Destination (Join-Path $DashboardPublicDir "registry.json") -Force
}

Write-Host "[STATS] Exported DB, Active Sessions, and Registry to Dashboard/public" -ForegroundColor Green
