# SUB-RUN-02_MR-01_Planning__Triage.ps1 (Vorce 3.0)
# Koordiniert und aggregiert die Triage-PART-RUNs.
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
    @{
        name = "PART-RUN-01_MR-01_Planning__Triage__FilterIssues"
        script = Join-Path $PSScriptRoot "PART-RUNS/PART-RUN-01_MR-01_Planning__Triage__FilterIssues.ps1"
    }
)

return Invoke-VorceSubRunSequential -SubRunName "SUB-RUN-02_MR-01_Planning__Triage" -PartRuns $partRuns -ConfigBag $ConfigBag -ParentState $ParentState
