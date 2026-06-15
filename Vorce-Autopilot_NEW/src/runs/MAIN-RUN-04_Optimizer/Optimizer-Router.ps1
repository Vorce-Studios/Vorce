# Optimizer-Router.ps1 (Vorce 3.0)
# Dynamisches Routing für MAIN-RUN-04_Optimizer basierend auf Performance-Daten
[CmdletBinding()]
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

Write-VorceStep -Message "Starte Optimizer-Routing..." -Status "RUN"

# Definiere die Sub-RUNs (immer beide aktiv)
$subRuns = @(
    @{
        id="01";
        name="PerformanceDataCollection";
        script="src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection/SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection.ps1"
    },
    @{
        id="02";
        name="SystemAnalysis";
        script="src/runs/MAIN-RUN-04_Optimizer/SUB-RUNS/SUB-RUN-02_MR-04_Optimizer__SystemAnalysis/SUB-RUN-02_MR-04_Optimizer__SystemAnalysis.ps1"
    }
)

# Optimizer-Module sollten immer beide ausgeführt werden
Write-VorceStep -Message "Geplante Optimizer-Sub-RUNs: $($subRuns.Count)" -Status "INFO"
foreach ($sub in $subRuns) {
    Write-VorceStep -Message "  - $($sub.name) (ID: $($sub.id))" -Status "INFO"
}

# Sortiere die Sub-RUNs nach ID
$subRuns = $subRuns | Sort-Object { [int]$_.id }

# Rückgabe: Array von Sub-RUN Definitionen
return $subRuns
