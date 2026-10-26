# PART-RUN-01_FilterIssues.ps1 (Vorce 3.0)
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
$VarDir = $global:VarDir

. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "utils/TriageUtils.ps1")

# Lade Daten
$issuesPath = Join-Path $VarDir "db/github-issues.json"

if (-not (Test-Path $issuesPath)) { return @{ error = "No issues found" } }
$issues = Get-Content $issuesPath -Raw | ConvertFrom-Json
$triaged = Get-VorceTriagedIssues -Issues $issues -Config $ConfigBag.Config

# Speichere Ergebnis
$triagedPath = Join-Path $VarDir "db/triaged-issues.json"
$triaged | ConvertTo-Json -Depth 10 | Set-Content $triagedPath -Encoding UTF8

return @{
    triaged_count = $triaged.Count
    timestamp = (Get-Date).ToString("o")
}
