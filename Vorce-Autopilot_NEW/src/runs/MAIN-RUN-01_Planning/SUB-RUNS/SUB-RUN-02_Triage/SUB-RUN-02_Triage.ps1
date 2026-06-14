# SUB-RUN-02_Triage.ps1 (Vorce 3.0)
# Filtert und klassifiziert GitHub Issues
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
$ScriptDir = $PSScriptRoot

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "utils/TriageUtils.ps1")

Write-VorceStep -Message "Starte Triage..." -Status "RUN"

# 1. Lade Issues aus var/db/github-issues.json
$issuesFile = Join-Path $global:VarDir "db/github-issues.json"
if (-not (Test-Path $issuesFile)) {
    Write-VorceStep -Message "Keine Issues zum Triagen gefunden." -Status "WARN"
    return @{ status="no_issues"; triaged=@(); count=0 }
}

try {
    $issues = Get-Content $issuesFile -Raw | ConvertFrom-Json
    if (-not ($issues -is [array])) {
        $issues = @($issues)
    }
} catch {
    Write-VorceStep -Message "Fehler beim Lesen von github-issues.json: $($_.Exception.Message)" -Status "ERROR"
    return @{ status="error"; error=$_.Exception.Message; triaged=@(); count=0 }
}

# 2. Rufe Get-VorceTriagedIssues auf mit Filterregeln
$triagedIssues = Get-VorceTriagedIssues -Issues $issues -FilterRules $ConfigBag.Config.issue_filters

# 3. Speichere Ergebnis in var/db/triaged-issues.json
$triagedDir = Join-Path $global:VarDir "db"
if (-not (Test-Path $triagedDir)) {
    New-Item -ItemType Directory -Path $triagedDir -Force | Out-Null
}

$triagedIssues | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $triagedDir "triaged-issues.json") -Encoding UTF8

# 4. Gib State mit Status und Anzahl zurück
$triageResult = @{
    status = "completed"
    triaged = $triagedIssues
    count = $triagedIssues.Count
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Triage abgeschlossen: $($triageResult.count) Issues triaged." -Status "OK"
return $triageResult
