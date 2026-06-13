[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
    [ValidateSet("Bug", "Feature", "Fix", "Polish", "Refactor", "Test")][string]$TaskType = "Feature",
    [ValidateSet("A", "B", "C")][string]$Priority = "B",
    [string]$Agent = "gemini_cli",
    [ValidateSet("simple", "detailed", "n_a")][string]$ReviewType = "simple",
    [ValidateSet("", "autopilot:audit", "autopilot:optimizer")][string]$OriginLabel = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "..")

. (Join-Path $ScriptDir "src/lib/naming-convention.ps1")
. (Join-Path $ScriptDir "src/lib/github-client.ps1")
. (Join-Path $ScriptDir "src/lib/project-manager.ps1")

if (-not (Test-VorceIssueTitle -Title $Title)) {
    $issues = @(Get-AllGitHubIssues -Repository $Repository -Limit 1000)
    $nextId = Get-NextVorceIssueId -Issues $issues
    $Title = Format-VorceIssueTitle -Type "default" -Id $nextId -Title $Title
}

$result = New-VorceManagedIssue -Repository $Repository -Title $Title -Body $Body -TaskType $TaskType -Priority $Priority -Agent $Agent -ReviewType $ReviewType -OriginLabel $OriginLabel
$result | ConvertTo-Json -Compress
