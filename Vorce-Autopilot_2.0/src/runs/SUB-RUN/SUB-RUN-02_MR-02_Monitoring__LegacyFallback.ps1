# src/runs/SUB-RUN/SUB-RUN-02_MR-02_Monitoring__LegacyFallback.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
Write-Host "[SUB-RUN] Fuehre Legacy Monitoring durch..." -ForegroundColor Yellow
if (-not (Get-Command Invoke-MonitoringWakeUp -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "../../phases/monitoring-wakeup.ps1") }
Invoke-MonitoringWakeUp -State $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun -SkipSync
