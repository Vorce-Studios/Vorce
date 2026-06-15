# src/runs/ROUTER/ROUTER_MAIN-RUN-03_Audit.ps1
# Smart Router fuer den Audit-Modus (QA-Manager)

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
if (-not (Get-Command Test-ObjectProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $ScriptDir "src/lib/state/state-manager.ps1")
}
param(
    [object]$GlobalState,
    [object]$Config,
    [object]$MainState
)

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
. (Join-Path $ScriptDir "src/lib/utils/planning-utils.ps1")

Write-Host "`n[ROUTER] Validiere dynamische Routing-Regeln fuer Audit..." -ForegroundColor Magenta

$definitions = @()
$idx = 1

function Add-Def {
    param([string]$Name, [string]$Script)
    $Script:definitions += @{
        id     = "{0:D2}" -f $Script:idx
        name   = $Name
        script = $Script
    }
    $Script:idx++
}

# 1. DataSync laeuft IMMER
Add-Def -Name "DataSync" -Script "src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-01_MR-03_Audit__DataSync/SUB-RUN-01_MR-03_Audit__DataSync.ps1"
Write-Host "[ROUTER]   -> DataSync: ENABLED (Laeuft immer)" -ForegroundColor Green

# 2. ComplianceCheck
Add-Def -Name "ComplianceCheck" -Script "src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-02_MR-03_Audit__ComplianceCheck/SUB-RUN-02_MR-03_Audit__ComplianceCheck.ps1"
Write-Host "[ROUTER]   -> ComplianceCheck: ENABLED" -ForegroundColor Green

# 3. JulesSupervision: Nur wenn es aktive Jules-Sessions gibt (geprueft via GlobalState)
$julesDelegations = @($GlobalState.active_delegations | Where-Object {
    $at = if ($_.PSObject.Properties.Name -contains "agent_type" -and $_.agent_type) { [string]$_.agent_type } else { "jules" }
    $at -eq "jules"
})
if ($julesDelegations.Count -gt 0) {
    Add-Def -Name "JulesSupervision" -Script "src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-03_MR-03_Audit__JulesSupervision/SUB-RUN-03_MR-03_Audit__JulesSupervision.ps1"
    Write-Host "[ROUTER]   -> JulesSupervision: ENABLED ($($julesDelegations.Count) aktive Jules-Sessions)" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> JulesSupervision: DISABLED (Keine aktiven Jules-Sessions)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_JulesSupervision"] = @{ reason = "no_jules_delegations"; timestamp = (Get-Date).ToString('o') }
}

# 4. AlertDisposition laeuft IMMER (generiert finales Output)
Add-Def -Name "AlertDisposition" -Script "src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-04_MR-03_Audit__AlertDisposition/SUB-RUN-04_MR-03_Audit__AlertDisposition.ps1"
Write-Host "[ROUTER]   -> AlertDisposition: ENABLED (Laeuft immer)" -ForegroundColor Green

return $definitions
