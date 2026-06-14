# src/runs/MAIN-RUN/MAIN-RUN-05_MemoryOptimization.ps1
param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$QuotaRegistry,
    [switch]$DryRun
)

$MainRunName = "MAIN-RUN-05_MemoryOptimization"
Write-Host "`n=== Starte $MainRunName ===" -ForegroundColor Cyan

# Hole zugehoerige SUB-RUNS ueber den Router
$routerScript = Join-Path $Script:OrchestratorRoot "src/runs/ROUTER/ROUTER_MAIN-RUN-05_MemoryOptimization.ps1"
$subRunDefinitions = @()

if (Test-Path $routerScript) {
    $subRunDefinitions = & $routerScript -GlobalState $GlobalState -Config $Config -MainState $null
} else {
    Write-Warning "[MAIN-RUN-05] Router nicht gefunden: ROUTER_MAIN-RUN-05_MemoryOptimization.ps1"
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
