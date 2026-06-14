# src/runs/MAIN-RUN/MAIN-RUN-01_Planning.ps1
param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$QuotaRegistry,
    [switch]$DryRun
)

$ScriptDir = $PSScriptRoot
$OrchDir = Join-Path $ScriptDir "../../core"

# Lade Orchestrator
. (Join-Path $OrchDir "Invoke-MainRun.ps1")

# Fuehre den Main Run aus
return Invoke-MainRun -MainRunName "MAIN-RUN-01_Planning" -GlobalState $GlobalState -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
