# src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__LegacyFallback.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "[SUB-RUN] Fuehre Legacy Planning Analyse & Delegation durch..." -ForegroundColor Yellow

# Importiere notwendige Module
if (-not (Get-Command Invoke-PlanningWakeUp -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../phases/planning-wakeup.ps1")
}

# Rufe die Hauptlogik auf (mit SkipSync, da wir SR-01 haben)
Invoke-PlanningWakeUp `
    -State $GlobalState `
    -Config $Config `
    -QuotaRegistry $QuotaRegistry `
    -DryRun:$DryRun `
    -SkipSync `
    -MainState $MainState `
    -SubState $SubState

$SubState.artifacts += @{
    type = "DelegationReport"
    timestamp = (Get-Date).ToString('o')
    queue_size = @($GlobalState.working_queue).Count
}
