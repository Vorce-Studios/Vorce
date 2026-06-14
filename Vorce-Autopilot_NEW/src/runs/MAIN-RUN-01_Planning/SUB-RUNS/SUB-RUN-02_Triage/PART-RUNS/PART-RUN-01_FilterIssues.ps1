# PART-RUN-01_FilterIssues.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$global:VorceRoot = Join-Path $PSScriptRoot "../../../.."
$ScriptDir = $PSScriptRoot
$VarDir = Join-Path $global:VorceRoot "var"

. (Join-Path $global:VorceRoot "src/lib/utils/StatusPrinter.ps1")
. (Join-Path $global:VorceRoot "src/lib/utils/TriageUtils.ps1")

# Lade Daten
$issuesPath = Join-Path $VarDir "db/github-issues.json"
$configPath = Join-Path $VarDir "config/autopilot-config.json"

if (-not (Test-Path $issuesPath)) { return @{ error = "No issues found" } }
$issues = Get-Content $issuesPath -Raw | ConvertFrom-Json
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$triaged = Get-VorceTriagedIssues -Issues $issues -Config $config

# Speichere Ergebnis
$triagedPath = Join-Path $VarDir "db/triaged-issues.json"
$triaged | ConvertTo-Json -Depth 10 | Set-Content $triagedPath -Encoding UTF8

return @{ 
    triaged_count = $triaged.Count 
    timestamp = (Get-Date).ToString("o") 
}
