# src/runs/SUB-RUN/SUB-RUN-01_MR-03_Audit__DataSync.ps1
# Sammelt Daten für die nachfolgenden Audit-Schritte (Issues, PRs, Delegierungen)
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-01 DataSync: Sammle Audit-Kontextdaten..." -ForegroundColor Cyan

$repo = $Config.repository
$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"

$issuesData = ""
$prsData = ""
$delegationsData = ""

# 1. Issues
$cachedIssuePath = Join-Path $VarDbDir "github-issues.json"
if (Test-Path $cachedIssuePath) {
    try {
        $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $issuesRaw -and ($issuesRaw -is [System.Array] -or $issuesRaw -is [System.Collections.IList])) {
            $issuesData = ($issuesRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo } | ForEach-Object { "- Issue #$($_.number) [$($_.state)]: $($_.title)" }) -join "`n"
        }
    } catch { Write-Warning "[AUDIT] Fehler beim Lesen der gecachten Issues." }
}

# 2. PRs
$cachedPrPath = Join-Path $VarDbDir "pull-requests.json"
if (Test-Path $cachedPrPath) {
    try {
        $prsRaw = Get-Content -LiteralPath $cachedPrPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $prsRaw -and ($prsRaw -is [System.Array] -or $prsRaw -is [System.Collections.IList])) {
            $prsData = ($prsRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo } | ForEach-Object { "- PR #$($_.number) [$($_.mergeable)]: $($_.title)" }) -join "`n"
        }
    } catch { Write-Warning "[AUDIT] Fehler beim Lesen der gecachten PRs." }
}

# 3. Active Delegations
if ($GlobalState.PSObject.Properties.Name -contains "active_delegations" -and $null -ne $GlobalState.active_delegations) {
    $delegationsData = ($GlobalState.active_delegations | ForEach-Object { "- Issue #$($_.issue_number) an $($_.agent_type) (Session: $($_.jules_session_id)) - Status: $($_.jules_state)" }) -join "`n"
}

# Speichere die gesammelten Strings im MainState fuer naechste Sub-Runs
$MainState | Add-Member -MemberType NoteProperty -Name "AuditIssuesData" -Value $issuesData -Force
$MainState | Add-Member -MemberType NoteProperty -Name "AuditPrsData" -Value $prsData -Force
$MainState | Add-Member -MemberType NoteProperty -Name "AuditDelegationsData" -Value $delegationsData -Force

Write-Host "[AUDIT] Daten synchronisiert (Issues, PRs, Delegierungen im Speicher)." -ForegroundColor DarkGray
$SubState.status = "completed"
