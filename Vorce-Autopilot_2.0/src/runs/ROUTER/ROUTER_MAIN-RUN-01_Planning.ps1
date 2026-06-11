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
Add-Def -Name "DataSync" -Script "src/runs/SUB-RUN/SUB-RUN-01_MR-01_Planning__DataSync.ps1"
Write-Host "[ROUTER]   -> DataSync: ENABLED (Laeuft immer)" -ForegroundColor Green

# 2. Triage läuft immer (prüft Eskalationen und Konflikte intern)
Add-Def -Name "Triage" -Script "src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__Triage.ps1"
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
        # Grobe Schätzung reicht für den Router. Genauere Prüfung passiert in SR-03
        $issuesCount = $openIssues.Count
    } catch {}
}

if ($issuesCount -lt 3) {
    Add-Def -Name "Strategy" -Script "src/runs/SUB-RUN/SUB-RUN-03_MR-01_Planning__Strategy.ps1"
    Write-Host "[ROUTER]   -> Strategy: ENABLED ($issuesCount < 3 Issues)" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> Strategy: DISABLED ($issuesCount >= 3 Issues vorhanden)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_Strategy"] = @{ reason = "enough_issues"; timestamp = (Get-Date).ToString('o') }
}

# 4. Delegation läuft immer
Add-Def -Name "Delegation" -Script "src/runs/SUB-RUN/SUB-RUN-04_MR-01_Planning__Delegation.ps1"
Write-Host "[ROUTER]   -> Delegation: ENABLED (Laeuft immer)" -ForegroundColor Green

# 5. Optimization läuft dynamisch basierend auf Timestamps
$optHours = if ($Config.wake_intervals.PSObject.Properties.Name -contains "optimizer_hours" -and $Config.wake_intervals.optimizer_hours) { [int]$Config.wake_intervals.optimizer_hours } else { 12 }
$runAnalysis = $false
$forceOptimizer = $false
if ((Test-ObjectProperty -Object $GlobalState -Name "run_control") -and (Test-ObjectProperty -Object $GlobalState.run_control -Name "force_optimizer") -and [bool]$GlobalState.run_control.force_optimizer) {
    $forceOptimizer = $true
    $runAnalysis = $true
}

if (-not ($GlobalState.PSObject.Properties.Name -contains "last_optimizer_analysis_at") -or [string]::IsNullOrWhiteSpace([string]$GlobalState.last_optimizer_analysis_at)) {
    $runAnalysis = $true
} elseif (-not $forceOptimizer) {
    try {
        $lastAt = [datetimeoffset]::Parse([string]$GlobalState.last_optimizer_analysis_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $ageHours = ((Get-Date) - $lastAt.LocalDateTime).TotalHours
        if ($ageHours -ge $optHours) {
            $runAnalysis = $true
        }
    } catch {
        $runAnalysis = $true
    }
}

if ($runAnalysis) {
    Add-Def -Name "Optimization" -Script "src/runs/SUB-RUN/SUB-RUN-05_MR-01_Planning__Optimization.ps1"
    Write-Host "[ROUTER]   -> Optimization: ENABLED (Timeout/Force aktiv)" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> Optimization: DISABLED (Letzter Run vor < $optHours Std)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_Optimization"] = @{ reason = "timeout_not_reached"; timestamp = (Get-Date).ToString('o') }
}

return $definitions
