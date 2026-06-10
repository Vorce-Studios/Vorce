# src/runs/ROUTER/ROUTER_MAIN-RUN-03_Audit.ps1
# Router fuer die Audit-Phase

param(
    [Parameter(Mandatory)][object]$GlobalState,
    [Parameter(Mandatory)][object]$Config,
    [object]$MainState
)

Write-Host "[ROUTER] Evaluierung der SUB-RUNS fuer Audit..." -ForegroundColor DarkGray

$subRuns = @()
$idx = 1

$routerCfg = $null
if ($Config.PSObject.Properties.Name -contains "router_rules" -and 
    $Config.router_rules.PSObject.Properties.Name -contains "Audit") {
    $routerCfg = $Config.router_rules.Audit
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
    Write-Warning "[ROUTER] Keine Config-Regeln fuer 'Audit' gefunden. Nutze Defaults."
    $subRuns += @{
        id     = "01"
        name   = "ConsistencyAudit"
        script = "src/runs/SUB-RUN/SUB-RUN-01_MR-03_Audit__ConsistencyAudit.ps1"
    }
    $subRuns += @{
        id     = "02"
        name   = "LegacyAudit"
        script = "src/runs/SUB-RUN/SUB-RUN-02_MR-03_Audit__LegacyFallback.ps1"
    }
}

Write-Host "[ROUTER] Audit: $($subRuns.Count) Sub-Run(s) identifiziert." -ForegroundColor DarkGray
return $subRuns
