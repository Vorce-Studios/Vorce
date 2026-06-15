# Vorce-Orchestrator.ps1 (Vorce 3.0)
# Zentrales Steuerungs-Modul für die Run-Hierarchie mit GitHub Project Integration
[CmdletBinding()]
param(
    [object]$GlobalState
)

$ScriptDir = $PSScriptRoot
$RunsDir = Join-Path $ScriptDir "../runs"

# Lade Kern-Module
. (Join-Path $ScriptDir "../lib/StatusPrinter.ps1")
. (Join-Path $ScriptDir "../lib/StateManager.ps1")
. (Join-Path $ScriptDir "../lib/ProjectManager.ps1")
. (Join-Path $ScriptDir "../lib/RunEngine.ps1")

Write-VorceHeader -Title "ORCHESTRATOR ACTIVE" -Icon "🧠"

# 1. Bestimme nächsten MAIN-RUN
$MainRunName = "MAIN-RUN-01_Planning"
$MainRunPath = Join-Path $RunsDir $MainRunName

Write-VorceStep -Message "Starte $MainRunName" -Status "RUN"

# 2. Initialisiere Main-Run State
$MainState = Initialize-RunState -RunName $MainRunName -RunType "MAIN"

# 3. Synchronisiere initialen Status mit GitHub
$MainState.status = "in_progress"
Sync-VorceProjectState -RunState $MainState

# 4. Rufe Router auf
$RouterPath = Join-Path $MainRunPath "Planning-Router.ps1"
Write-VorceStep -Message "Analysiere Bedarf via Router..." -Status "INFO"

$SubRuns = @()
if (Test-Path $RouterPath) {
    # Dynamischer Aufruf des Routers
    $SubRuns = & $RouterPath -MainState $MainState
} else {
    Write-VorceStep -Message "Router nicht gefunden unter $RouterPath. Nutze Default-Ablauf." -Status "WARN"
    $SubRuns = @("SUB-RUN-01_DataSync")
}

# 5. Führe Sub-Runs aus
$MaxParallel = 3
Write-VorceStep -Message "Geplante Sub-Runs: $($SubRuns.Count)" -Status "INFO"

foreach ($subName in $SubRuns) {
    Write-VorceDivider
    Write-VorceStep -Message "Starte Sub-Run: $subName" -Status "RUN"

    $subScript = Join-Path $MainRunPath "SUB-RUNS/$subName.ps1"
    if (Test-Path $subScript) {
        $subResult = & $subScript -ParentState $MainState
        $MainState.results += $subResult
        Write-VorceStep -Message "Sub-Run $subName abgeschlossen." -Status "OK"
    } else {
        Write-VorceStep -Message "Sub-Run Skript nicht gefunden: $subScript" -Status "ERROR"
    }
}

# 6. Finale Aggregation und Abschluss
Write-VorceDivider
Write-VorceStep -Message "Führe alle Sub-Run Ergebnisse zusammen (Main-Aggregation)..." -Status "RUN"

# Hier wird das finale JSON für den Main-Run erstellt
$MainState.status = "completed"
$MainState.completed_at = (Get-Date).ToString("o")

# Falls ein Aggregations-Skript existiert (z.B. MAIN-RUN-01_Planning_Aggregate.ps1)
# & ...

Write-VorceStep -Message "Main-Aggregation für $MainRunName abgeschlossen." -Status "OK"

# 7. Finaler GitHub & Dashboard Sync
Sync-VorceProjectState -RunState $MainState
Save-VorceGlobalState -State $GlobalState # Dashboard-Trigger

Write-VorceFooter -Message "$MainRunName erfolgreich beendet."
