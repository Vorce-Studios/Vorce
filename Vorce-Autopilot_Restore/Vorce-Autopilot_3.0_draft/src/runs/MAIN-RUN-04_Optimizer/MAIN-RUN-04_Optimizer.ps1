# src/runs/MAIN-RUN/MAIN-RUN-04_Optimizer.ps1
param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$QuotaRegistry,
    [switch]$DryRun
)

$ScriptDir = $PSScriptRoot
$OrchDir = Join-Path $ScriptDir "../../core"
. (Join-Path $OrchDir "Invoke-MainRun.ps1")

return Invoke-MainRun -MainRunName "MAIN-RUN-04_Optimizer" -GlobalState $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
