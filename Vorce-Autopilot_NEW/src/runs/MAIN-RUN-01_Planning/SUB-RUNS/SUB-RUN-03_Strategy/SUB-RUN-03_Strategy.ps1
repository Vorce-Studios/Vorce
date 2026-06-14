# SUB-RUN-03_Strategy.ps1 (Vorce 3.0)
[CmdletBinding()]
param([object]$ParentState)

$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "../../../lib/StatusPrinter.ps1")
. (Join-Path $ScriptDir "../../../lib/RunEngine.ps1")

$PartRuns = @(
    @{ name="CreateProposal"; script=(Join-Path $ScriptDir "../PART-RUNS/PART-RUN-04_CreateProposal.ps1") }
)

# Strategie-Phase läuft meist sequentiell pro Issue, daher MaxParallel 1
$Result = Invoke-VorceSubRunParallel -SubRunName "Strategy" -PartRuns $PartRuns -MaxParallel 1

return $Result
