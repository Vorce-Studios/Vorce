# SUB-RUN-02_MR-04_Optimizer__SystemAnalysis.ps1 (Vorce 3.0)
# Koordiniert die PART-RUNs dieses SUB-RUNs.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "engines/RunEngine.ps1")

$partRuns = @(
    @{ name = "PART-RUN-01_MR-04_Optimizer__SystemAnalysis__AnalyzeSystemPerformance"; script = (Join-Path $PSScriptRoot "PART-RUNS/PART-RUN-01_MR-04_Optimizer__SystemAnalysis__AnalyzeSystemPerformance.ps1") }
)

return Invoke-VorceSubRunSequential -SubRunName "SUB-RUN-02_MR-04_Optimizer__SystemAnalysis" -PartRuns $partRuns -ConfigBag $ConfigBag -ParentState $ParentState

