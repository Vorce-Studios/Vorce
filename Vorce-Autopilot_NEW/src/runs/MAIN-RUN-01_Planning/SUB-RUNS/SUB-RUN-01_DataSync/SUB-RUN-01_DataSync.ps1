# SUB-RUN-01_DataSync.ps1 (Vorce 3.0)
[CmdletBinding()]
param([object]$ParentState)

$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "../../../lib/StatusPrinter.ps1")
. (Join-Path $ScriptDir "../../../lib/RunEngine.ps1")

$PartRuns = @(
    @{ name="FetchIssues"; script=(Join-Path $ScriptDir "../PART-RUNS/PART-RUN-01_FetchIssues.ps1") },
    @{ name="FetchPRs";    script=(Join-Path $ScriptDir "../PART-RUNS/PART-RUN-02_FetchPRs.ps1") }
)

$Result = Invoke-VorceSubRunParallel -SubRunName "DataSync" -PartRuns $PartRuns -MaxParallel 2

return $Result
