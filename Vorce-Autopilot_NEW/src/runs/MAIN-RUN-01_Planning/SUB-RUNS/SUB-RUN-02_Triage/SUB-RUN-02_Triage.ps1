# SUB-RUN-02_Triage.ps1 (Vorce 3.0)
[CmdletBinding()]
param([object]$ParentState)

$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "../../../lib/StatusPrinter.ps1")
. (Join-Path $ScriptDir "../../../lib/RunEngine.ps1")

$PartRuns = @(
    @{ name="FilterIssues"; script=(Join-Path $ScriptDir "../PART-RUNS/PART-RUN-03_FilterIssues.ps1") }
)

$Result = Invoke-VorceSubRunParallel -SubRunName "Triage" -PartRuns $PartRuns -MaxParallel 1

return $Result
