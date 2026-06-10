# SR-00_LegacyMonitoringFallback.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
Write-Host "[FALLBACK] Rufe Legacy Monitoring Wakeup auf..." -ForegroundColor Gray
Invoke-MonitoringWakeUp -State $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
