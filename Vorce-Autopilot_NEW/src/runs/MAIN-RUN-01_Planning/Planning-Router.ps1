# Planning-Router.ps1 (Vorce 3.0)
# Dynamisches Routing für MAIN-RUN-01_Planning basierend auf Config und Daten

param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$MainState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")

Write-VorceStep -Message "Starte Planning-Routing..." -Status "RUN"

# Definiere die Sub-RUNs (Standard-Liste)
$subRuns = @(
    @{ id="01"; name="DataSync"; script="src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_DataSync/SUB-RUN-01_DataSync.ps1" },
    @{ id="02"; name="Triage"; script="src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-02_Triage/SUB-RUN-02_Triage.ps1" },
    @{ id="04"; name="Delegation"; script="src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-04_Delegation/SUB-RUN-04_Delegation.ps1" }
)

# Prüfe ob Strategy aktiviert werden soll
$issuesFile = Join-Path $global:VarDir "db/github-issues.json"
$maxIssuesPerCycle = $ConfigBag.Config.max_issues_per_planning_cycle

if (Test-Path $issuesFile) {
    try {
        $issues = Get-Content $issuesFile -Raw | ConvertFrom-Json
        $issueCount = if ($issues -is [array]) { $issues.Count } else { 1 }

        Write-VorceStep -Message "Aktuelle Issues in Pipeline: $issueCount / Max: $maxIssuesPerCycle" -Status "INFO"

        # Strategy aktivieren wenn weniger als max_issues_per_planning_cycle Issues vorhanden
        if ($issueCount -lt $maxIssuesPerCycle) {
            $subRuns += @{
                id="03";
                name="Strategy";
                script="src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_Strategy/SUB-RUN-03_Strategy.ps1"
            }
            Write-VorceStep -Message "Strategy aktiviert (für $($maxIssuesPerCycle - $issueCount) neue Issues)" -Status "OK"
        } else {
            Write-VorceStep -Message "Strategy deaktiviert (Pipeline voll)" -Status "WARN"
        }
    } catch {
        Write-VorceStep -Message "Fehler beim Lesen von github-issues.json: $($_.Exception.Message)" -Status "ERROR"
        # Strategy wird nicht aktiviert
    }
} else {
    Write-VorceStep -Message "Keine Issues vorhanden, Strategy aktiviert" -Status "INFO"
    $subRuns += @{
        id="03";
        name="Strategy";
        script="src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_Strategy/SUB-RUN-03_Strategy.ps1"
    }
}

# Sortiere die Sub-RUNs nach ID
$subRuns = $subRuns | Sort-Object { [int]$_.id }

Write-VorceStep -Message "Geplante Sub-RUNs: $($subRuns.Count)" -Status "INFO"
foreach ($sub in $subRuns) {
    Write-VorceStep -Message "  - $($sub.name) (ID: $($sub.id))" -Status "INFO"
}

# Rückgabe: Array von Sub-RUN Definitionen
return $subRuns
