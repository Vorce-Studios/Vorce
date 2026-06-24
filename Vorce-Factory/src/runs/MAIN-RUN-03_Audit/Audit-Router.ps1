# Audit router using the shared deterministic router contract.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$MainState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir 'engines/RouterEngine.ps1')

$rules = @($ConfigBag.Config.router_rules.Audit)
$decisions = @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-03_Audit' -ConfigBag $ConfigBag -MainState $MainState -Rules $rules)
Set-VorceRouterDecisionMetadata -MainState $MainState -RouterKey 'Audit' -Decisions $decisions -DecisionTimestamp $ConfigBag.Timestamp

return @($decisions | Where-Object { $_.active })
