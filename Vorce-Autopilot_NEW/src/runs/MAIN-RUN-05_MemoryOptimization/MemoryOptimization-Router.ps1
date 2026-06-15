# MemoryOptimization-Router.ps1 (Vorce 3.0)
# Dynamisches Routing für MAIN-RUN-05_MemoryOptimization
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

Write-VorceStep -Message "Starte MemoryOptimization-Routing..." -Status "RUN"

# Definiere die Sub-RUNs (immer aktiv)
$subRuns = @(
    @{
        id="01";
        name="MemoryMaintenance";
        script="src/runs/MAIN-RUN-05_MemoryOptimization/SUB-RUNS/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance.ps1"
    }
)

# MemoryOptimization sollte immer laufen um Token zu sparen
Write-VorceStep -Message "Geplante MemoryOptimization-Sub-RUNs: $($subRuns.Count)" -Status "INFO"
foreach ($sub in $subRuns) {
    Write-VorceStep -Message "  - $($sub.name) (ID: $($sub.id))" -Status "INFO"
}

# Sortiere die Sub-RUNs nach ID
$subRuns = $subRuns | Sort-Object { [int]$_.id }

# Rückgabe: Array von Sub-RUN Definitionen
return $subRuns