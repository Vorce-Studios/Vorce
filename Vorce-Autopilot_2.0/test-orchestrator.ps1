# Test-Orchestrator.ps1
# Simuliert einen Main-Run Lauf mit dem neuen hierarchischen Orchestrator

$ScriptDir = $PSScriptRoot
$LibDir = Join-Path $ScriptDir "src/lib"
$OrchDir = Join-Path $ScriptDir "src/orchestrator"
$RouterDir = Join-Path $ScriptDir "src/router"

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

# Neu: Orchestrator & Router
. (Join-Path $OrchDir "Invoke-MainRun.ps1")
. (Join-Path $RouterDir "Invoke-MainRunRouter.ps1")

# Lade Config
$configPath = Join-Path $ScriptDir "config/autopilot-config.json"
$Config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Registry = Read-QuotaRegistry
$GlobalState = Initialize-AutopilotState

Write-Host "--- Starte Hierarchischen Orchestrator Test ---" -ForegroundColor Magenta

# Führe Planning Run aus (Dry-Run)
$planningResult = Invoke-MainRun -MainRunName "Planning" -GlobalState $GlobalState -Config $Config -QuotaRegistry $Registry -DryRun

Write-Host "`n--- Testergebnis ---" -ForegroundColor Magenta
if ($null -ne $planningResult) {
    Write-Host "Status: $($planningResult.status)"
    Write-Host "Sub-Runs: $($planningResult.sub_runs.Count)"
} else {
    Write-Host "Status: FAILED (Result is NULL)" -ForegroundColor Red
}

$planningResult | ConvertTo-Json -Depth 5
