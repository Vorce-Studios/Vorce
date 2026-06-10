# Test-Orchestrator.ps1
# Simuliert einen Main-Run Lauf mit dem neuen hierarchischen Orchestrator

$ScriptDir = $PSScriptRoot
$LibDir = Join-Path $ScriptDir "src/lib"
$OrchDir = Join-Path $ScriptDir "src/orchestrator"

# Importiere Module (wie in autopilot.ps1)
. (Join-Path $LibDir "state-manager.ps1")
. (Join-Path $LibDir "quota-manager.ps1")
. (Join-Path $LibDir "cli-router.ps1")
. (Join-Path $LibDir "memory-store.ps1")
. (Join-Path $LibDir "deliberation-engine.ps1")
. (Join-Path $LibDir "autopilot-session-manager.ps1")
. (Join-Path $LibDir "autopilot-prompts.ps1")
. (Join-Path $LibDir "github-client.ps1")
. (Join-Path $LibDir "jules-client.ps1")
. (Join-Path $LibDir "naming-convention.ps1")
. (Join-Path $LibDir "project-manager.ps1")
. (Join-Path $ScriptDir "src/phases/planning-wakeup.ps1")
. (Join-Path $ScriptDir "src/phases/monitoring-wakeup.ps1")
. (Join-Path $ScriptDir "src/phases/audit-wakeup.ps1")

# Orchestrator (enthaelt Invoke-MainRun und Resolve-SubRunDefinitions)
. (Join-Path $OrchDir "Invoke-MainRun.ps1")

# Lade Config
$configPath = Join-Path $ScriptDir "config/autopilot-config.json"
$Config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Registry = Read-QuotaRegistry
$GlobalState = Initialize-AutopilotState

Write-Host "--- Starte Hierarchischen Orchestrator Test ---" -ForegroundColor Magenta

# Test 1: Planning Run (Dry-Run) via MAIN-RUN Skript
Write-Host "`n=== Test 1: Planning MAIN-RUN ===" -ForegroundColor Cyan
$planningResult = Invoke-MainRun -MainRunName "MAIN-RUN-01_Planning" -GlobalState $GlobalState -Config $Config -QuotaRegistry $Registry -DryRun

Write-Host "`n--- Planning Testergebnis ---" -ForegroundColor Magenta
if ($null -ne $planningResult) {
    Write-Host "Status: $($planningResult.status)" -ForegroundColor $(if ($planningResult.status -eq "completed") { "Green" } else { "Red" })
    Write-Host "Sub-Runs: $($planningResult.sub_runs.Count)"
} else {
    Write-Host "Status: FAILED (Result is NULL)" -ForegroundColor Red
}

# Test 2: Monitoring Run (Dry-Run)
Write-Host "`n=== Test 2: Monitoring MAIN-RUN ===" -ForegroundColor Cyan
$monResult = Invoke-MainRun -MainRunName "MAIN-RUN-02_Monitoring" -GlobalState $GlobalState -Config $Config -QuotaRegistry $Registry -DryRun

Write-Host "`n--- Monitoring Testergebnis ---" -ForegroundColor Magenta
if ($null -ne $monResult) {
    Write-Host "Status: $($monResult.status)" -ForegroundColor $(if ($monResult.status -eq "completed") { "Green" } else { "Red" })
    Write-Host "Sub-Runs: $($monResult.sub_runs.Count)"
} else {
    Write-Host "Status: FAILED (Result is NULL)" -ForegroundColor Red
}

# Test 3: Config-Fallback (kein Router-Skript)
Write-Host "`n=== Test 3: Config-Fallback Test (RunName ohne Router-Skript) ===" -ForegroundColor Cyan
$fallbackResult = Invoke-MainRun -MainRunName "Planning" -GlobalState $GlobalState -Config $Config -QuotaRegistry $Registry -DryRun

Write-Host "`n--- Fallback Testergebnis ---" -ForegroundColor Magenta
if ($null -ne $fallbackResult) {
    Write-Host "Status: $($fallbackResult.status) (erwartet: completed oder partial)" -ForegroundColor $(if ($fallbackResult.status -ne "failed") { "Green" } else { "Red" })
} else {
    Write-Host "Status: FAILED (Result is NULL)" -ForegroundColor Red
}

Write-Host "`n=== Alle Tests abgeschlossen ===" -ForegroundColor Magenta
