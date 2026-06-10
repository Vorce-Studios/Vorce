# SR-00_LegacyPlanningFallback.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
Write-Host "[FALLBACK] Rufe Legacy Planning Wakeup auf..." -ForegroundColor Gray
Invoke-PlanningWakeUp -State $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
