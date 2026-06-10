# SR-01_SystemHealthCheck.ps1
# Phase: Monitoring
# Aufgabe: Prüfung der Systemintegrität, Quotas und aktiven Sessions

param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "[SUB-RUN] Starte System Health Check..." -ForegroundColor Cyan

# 1. Quota Summary
if (-not (Get-Command Get-QuotaSummary -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../lib/quota-manager.ps1")
}
$summary = Get-QuotaSummary -Registry $QuotaRegistry
Write-Host $summary -ForegroundColor DarkGray

# 2. Sync Working Sessions & PRs
Write-Host "[HEALTH] Synchronisiere Working Sessions & PRs..." -ForegroundColor DarkGray
if (-not (Get-Command Sync-WorkingSessionsFromStatusFiles -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../phases/monitoring-wakeup.ps1")
}
if (-not (Get-Command Sync-VorcePullRequests -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../lib/github-client.ps1")
}
$VarDbDir = Join-Path $PSScriptRoot "../../var/db"
$repo = $Config.repository

Sync-WorkingSessionsFromStatusFiles -State $GlobalState -VarDbDir $VarDbDir
Sync-VorcePullRequests -Repo $repo -Config $Config

# 3. Check Active Delegations
$activeCount = @($GlobalState.active_delegations).Count
Write-Host "[HEALTH] Aktive Delegationen: $activeCount" -ForegroundColor $(if ($activeCount -gt 10) { "Yellow" } else { "Gray" })

# 3. Artifacts
$SubState.artifacts += @{
    name = "HealthStatus"
    timestamp = (Get-Date).ToString('o')
    quota_summary = $summary
    active_delegations = $activeCount
}

Write-Host "[SUB-RUN] System Health Check abgeschlossen." -ForegroundColor Green
