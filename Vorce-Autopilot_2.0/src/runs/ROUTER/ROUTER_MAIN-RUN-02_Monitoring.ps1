# src/runs/ROUTER/ROUTER_MAIN-RUN-02_Monitoring.ps1
# Router fuer die Monitoring-Phase

param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [object]$MainState
)

Write-Host "[ROUTER] Evaluierung der SUB-RUNS fuer Monitoring..." -ForegroundColor DarkGray

$subRuns = @()
$idx = 1

$routerCfg = $null
if ($Config.PSObject.Properties.Name -contains "router_rules" -and 
    $Config.router_rules.PSObject.Properties.Name -contains "Monitoring") {
    $routerCfg = $Config.router_rules.Monitoring
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
    Write-Warning "[ROUTER] Keine Config-Regeln fuer 'Monitoring' gefunden. Nutze Defaults."
    $subRuns += @{
        id     = "01"
        name   = "SystemHealthCheck"
        script = "src/runs/SUB-RUN/SUB-RUN-01_MR-02_Monitoring__SystemHealthCheck.ps1"
    }
    $subRuns += @{
        id     = "02"
        name   = "LegacyMonitoring"
        script = "src/runs/SUB-RUN/SUB-RUN-02_MR-02_Monitoring__LegacyFallback.ps1"
    }
}

Write-Host "[ROUTER] Monitoring: $($subRuns.Count) Sub-Run(s) identifiziert." -ForegroundColor DarkGray
return $subRuns
