# MemoryOptimization router using the shared deterministic router contract.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$MainState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir 'engines/RouterEngine.ps1')

$rules = @($ConfigBag.Config.router_rules.MemoryOptimization)
$decisions = @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-05_MemoryOptimization' -ConfigBag $ConfigBag -MainState $MainState -Rules $rules)
Set-VorceRouterDecisionMetadata -MainState $MainState -RouterKey 'MemoryOptimization' -Decisions $decisions -DecisionTimestamp $ConfigBag.Timestamp

return @($decisions | Where-Object { $_.active })
