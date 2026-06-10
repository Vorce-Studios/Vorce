# Invoke-MainRunRouter.ps1
# Router zur dynamischen Evaluierung von Sub-Runs basierend auf der Konfiguration

function Invoke-MainRunRouter {
    param(
        [string]$MainRunName,
        [object]$GlobalState,
        [object]$Config
    )

    Write-Host "[ROUTER] Evaluiere Sub-Runs fuer ${MainRunName}..." -ForegroundColor Cyan

    $subRuns = @()

    # Lade Regeln aus der Config
    if ($Config.PSObject.Properties.Name -contains "router_rules" -and $Config.router_rules.PSObject.Properties.Name -contains $MainRunName) {
        $rules = $Config.router_rules.$MainRunName
        foreach ($rule in $rules) {
            if ($rule.enabled) {
                # Zukuenftig: Hier koennen Kriterien wie $rule.condition evaluiert werden
                $subRuns += @{ name = $rule.name; script = $rule.script }
            } else {
                Write-Host "[ROUTER]   -> Sub-Run $($rule.name) deaktiviert (Config)." -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Warning "[ROUTER] Keine Regeln fuer $MainRunName in Config gefunden!"
    }

    Write-Host "[ROUTER] ${MainRunName}: $($subRuns.Count) Sub-Runs identifiziert." -ForegroundColor DarkGray
    return $subRuns
}

Export-ModuleMember -Function Invoke-MainRunRouter
