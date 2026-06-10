# SR-00_LegacyAuditFallback.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
Write-Host "[FALLBACK] Rufe Legacy Audit Wakeup auf..." -ForegroundColor Gray
Invoke-AuditWakeUp -State $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
