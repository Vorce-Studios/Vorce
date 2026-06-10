# src/runs/ROUTER/ROUTER_MAIN-RUN-01_Planning.ps1
param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [object]$MainState
)

Write-Host "[ROUTER] Evaluierung der SUB-RUNS fuer Planning..." -ForegroundColor DarkGray

$subRuns = @()

# Kriterium 1: Immer Context Gathering zu Beginn
$subRuns += @{
    id     = "01"
    name   = "ContextGathering"
    script = "src/runs/SUB-RUN/SUB-RUN-01_MR-01_Planning__ContextGathering.ps1"
}

# Kriterium 2: Check ob neue Issues oder re-planning erforderlich ist
# (Hier koennte komplexe Logik stehen, vorerst nutzen wir die Config-Enabled-Flags als Basis)
$routerCfg = $Config.router_rules.Planning
$legacyEnabled = $true
if ($null -ne $routerCfg) {
    $legacyDef = $routerCfg | Where-Object { $_.name -match "Legacy" }
    if ($null -ne $legacyDef) { $legacyEnabled = $legacyDef.enabled }
}

if ($legacyEnabled) {
    $subRuns += @{
        id     = "02"
        name   = "LegacyFallback"
        script = "src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__LegacyFallback.ps1"
    }
}

return $subRuns
