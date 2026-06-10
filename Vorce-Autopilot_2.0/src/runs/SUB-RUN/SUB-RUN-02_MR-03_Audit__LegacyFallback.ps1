# src/runs/SUB-RUN/SUB-RUN-02_MR-03_Audit__LegacyFallback.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
Write-Host "[SUB-RUN] Fuehre Legacy Audit durch..." -ForegroundColor Yellow
if (-not (Get-Command Invoke-AuditWakeUp -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "../../phases/audit-wakeup.ps1") }
Invoke-AuditWakeUp -State $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
