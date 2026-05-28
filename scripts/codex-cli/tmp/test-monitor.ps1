# Diagnose-Script fuer State-Properties
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = "c:\Users\Vinyl\Desktop\VJMapper\VjMapper\scripts\codex-cli"
. (Join-Path $ScriptDir "lib\state-manager.ps1")
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\cli-router.ps1")
. (Join-Path $ScriptDir "lib\memory-store.ps1")
. (Join-Path $ScriptDir "lib\deliberation-engine.ps1")
. (Join-Path $ScriptDir "lib\autopilot-session-manager.ps1")
. (Join-Path $ScriptDir "phases\monitoring-wakeup.ps1")

$State = Initialize-AutopilotState
Write-Host "Typ von State auf Root-Ebene: $($State.GetType().FullName)" -ForegroundColor Cyan
Write-Host "Properties auf State:" -ForegroundColor Cyan
$State.PSObject.Properties | ForEach-Object { Write-Host "  - $($_.Name) ($($_.TypeNameOfValue))" }

# Teste direkten Zugriff auf active_delegations
Write-Host "active_delegations Count: $($State.active_delegations.Count)" -ForegroundColor Cyan

# Simuliere den Loop aus monitoring-wakeup
$delegation = $State.active_delegations[0]
$issueNum = [int]$delegation.issue_number
Write-Host "Simuliere Update-DelegationState fuer Issue #$issueNum" -ForegroundColor Cyan

try {
    Update-DelegationState -State $State -IssueNumber $issueNum -JulesState "TEST_STATE"
    Write-Host "Update-DelegationState erfolgreich!" -ForegroundColor Green
} catch {
    Write-Host "Update-DelegationState FEHLGESCHLAGEN!" -ForegroundColor Red
    Write-Host "Fehlermeldung: $_" -ForegroundColor Red
    Write-Host "Exception details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "In welcher Datei: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
    Write-Host "Zeile: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
}
