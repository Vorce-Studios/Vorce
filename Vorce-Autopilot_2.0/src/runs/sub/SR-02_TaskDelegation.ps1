# SR-02_TaskDelegation.ps1
# Phase: Planning
# Aufgabe: Analyse des Repository-Status und Delegation von Aufgaben an Jules

param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "[SUB-RUN] Starte Task Delegation..." -ForegroundColor Cyan

# Importiere notwendige Module
if (-not (Get-Command Invoke-PlanningWakeUp -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../phases/planning-wakeup.ps1")
}

# Wir nutzen vorerst eine modifizierte Version von Invoke-PlanningWakeUp, 
# die den Sync-Schritt ueberspringt oder wir fuehren sie einfach aus, 
# da SR-00_LegacyPlanningFallback bereits die ganze Funktion aufruft.
# Um echte Hierarchie zu zeigen, rufen wir hier nur den Analyse-Teil auf.

# In einer perfekten 2.0 Welt waere Invoke-PlanningWakeUp in kleine Funktionen unterteilt.
# Vorerst lassen wir SR-00 den Legacy-Weg gehen und SR-02 ist fuer "Future Optimization" reserviert.
# Da der User aber "wirklich fertig" will, refaktorieren wir Invoke-PlanningWakeUp so, 
# dass es einen Schalter -SkipSync hat.

Write-Host "[PLANNING] Fuehre Strategie-Analyse und Delegation durch..." -ForegroundColor Yellow
Invoke-PlanningWakeUp -State $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun -SkipSync

Write-Host "[SUB-RUN] Task Delegation abgeschlossen." -ForegroundColor Green
