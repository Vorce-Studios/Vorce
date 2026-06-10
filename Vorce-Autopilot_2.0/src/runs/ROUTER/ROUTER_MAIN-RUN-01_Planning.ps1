# src/runs/ROUTER/ROUTER_MAIN-RUN-01_Planning.ps1
# Router fuer die Planning-Phase
# Entscheidet basierend auf Config und Systemzustand welche Sub-Runs laufen

param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [object]$MainState
)

Write-Host "[ROUTER] Evaluierung der SUB-RUNS fuer Planning..." -ForegroundColor DarkGray

$subRuns = @()
$idx = 1

# Lade Sub-Run-Definitionen aus der Config
$routerCfg = $null
if ($Config.PSObject.Properties.Name -contains "router_rules" -and 
    $Config.router_rules.PSObject.Properties.Name -contains "Planning") {
    $routerCfg = $Config.router_rules.Planning
}

if ($null -ne $routerCfg) {
    foreach ($rule in $routerCfg) {
        if ($rule.enabled) {
            $subRuns += @{
                id     = if ($rule.PSObject.Properties.Name -contains "id") { $rule.id } else { "{0:D2}" -f $idx }
                name   = $rule.name
                script = $rule.script
            }
            Write-Host "[ROUTER]   -> $($rule.name) aktiviert." -ForegroundColor Green
        } else {
            Write-Host "[ROUTER]   -> $($rule.name) deaktiviert (Config)." -ForegroundColor DarkGray
        }
        $idx++
    }
} else {
    # Hardcoded Fallback falls keine Config vorhanden
    Write-Warning "[ROUTER] Keine Config-Regeln fuer 'Planning' gefunden. Nutze Defaults."
    $subRuns += @{
        id     = "01"
        name   = "ContextGathering"
        script = "src/runs/SUB-RUN/SUB-RUN-01_MR-01_Planning__ContextGathering.ps1"
    }
    $subRuns += @{
        id     = "02"
        name   = "LegacyFallback"
        script = "src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__LegacyFallback.ps1"
    }
}

Write-Host "[ROUTER] Planning: $($subRuns.Count) Sub-Run(s) identifiziert." -ForegroundColor DarkGray
return $subRuns
