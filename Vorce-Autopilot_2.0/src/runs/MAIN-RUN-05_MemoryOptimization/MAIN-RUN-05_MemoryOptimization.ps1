# src/runs/MAIN-RUN/MAIN-RUN-05_MemoryOptimization.ps1
param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$QuotaRegistry,
    [switch]$DryRun
)

$MainRunName = "MAIN-RUN-05_MemoryOptimization"
Write-Host "`n=== Starte $MainRunName ===" -ForegroundColor Cyan

$ScriptDir = $PSScriptRoot
$global:OrchestratorRoot = (Resolve-Path (Join-Path $ScriptDir "../../..")).Path
$OrchDir = Join-Path $global:OrchestratorRoot "src/core"
. (Join-Path $OrchDir "Invoke-MainRun.ps1")

$routerScript = Join-Path $global:OrchestratorRoot "src/runs/$MainRunName/ROUTER_$MainRunName.ps1"
$subRunDefinitions = @()

if (Test-Path $routerScript) {
    $subRunDefinitions = & $routerScript -GlobalState $GlobalState -Config $Config -MainState $null
} else {
    Write-Warning "[MAIN-RUN-05] Router nicht gefunden: $routerScript"
    return
}

if ($subRunDefinitions.Count -eq 0) {
    Write-Host "[MAIN-RUN-05] Keine Routen aktiv. Ueberspringe MemoryOptimization." -ForegroundColor DarkGray
    return
}

# Nutze den Orchestrator fuer die Ausfuehrung
Invoke-MainRun `
    -MainRunName $MainRunName `
    -GlobalState $GlobalState `
    -Config $Config `
    -QuotaRegistry $QuotaRegistry `
    -ForceAll:$false `
    -DryRun:$DryRun
