# src/runs/ROUTER/ROUTER_MAIN-RUN-01_Planning.ps1
param(
    [object]$GlobalState,
    [object]$Config,
    [object]$MainState
)

Write-Host "`n[ROUTER] Validiere dynamische Routing-Regeln fuer Planning..." -ForegroundColor Magenta

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

# 1. DataSync läuft immer
Add-Def -Name "DataSync" -Script "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_MR-01_Planning__DataSync/SUB-RUN-01_MR-01_Planning__DataSync.ps1"
Write-Host "[ROUTER]   -> DataSync: ENABLED (Laeuft immer)" -ForegroundColor Green

# 2. Triage läuft immer (prüft Eskalationen und Konflikte intern)
Add-Def -Name "Triage" -Script "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-02_MR-01_Planning__Triage/SUB-RUN-02_MR-01_Planning__Triage.ps1"
Write-Host "[ROUTER]   -> Triage: ENABLED (Laeuft immer)" -ForegroundColor Green

# 3. Strategy läuft nur, wenn weniger als 3 Issues in der Pipeline sind
# Da DataSync erst später läuft, müssen wir auf den Stand vor DataSync schauen
$issuesCount = 0
$cachedIssuePath = Join-Path $PSScriptRoot "../../../var/db/github-issues.json"
if (Test-Path $cachedIssuePath) {
    try {
        $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $repo = $Config.repository
        $openIssues = @($issuesRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo })
        $includeLabels = @()
        if ((Test-ObjectProperty -Object $Config -Name "include_labels")) {
            $includeLabels = @($Config.include_labels)
        }
        $candidates = @($openIssues | Where-Object {
            if ($includeLabels.Count -eq 0) { return $true }
            $hasLabel = $false
            if ((Test-ObjectProperty -Object $_ -Name "labels")) {
                foreach ($lbl in $_.labels) {
                    if ($includeLabels -contains $lbl) { $hasLabel = $true; break }
                }
            }
            return $hasLabel
        })
        $issuesCount = $candidates.Count
    } catch {}
}

if ($issuesCount -lt 3) {
    Add-Def -Name "Strategy" -Script "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/SUB-RUN-03_MR-01_Planning__Strategy.ps1"
    Write-Host "[ROUTER]   -> Strategy: ENABLED ($issuesCount < 3 Issues)" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> Strategy: DISABLED ($issuesCount >= 3 Issues vorhanden)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_Strategy"] = @{ reason = "enough_issues"; timestamp = (Get-Date).ToString('o') }
}

# 4. Delegation läuft immer
Add-Def -Name "Delegation" -Script "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-04_MR-01_Planning__Delegation/SUB-RUN-04_MR-01_Planning__Delegation.ps1"
Write-Host "[ROUTER]   -> Delegation: ENABLED (Laeuft immer)" -ForegroundColor Green

return $definitions
