# PART-RUN-01_FetchIssues.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$global:VorceRoot = Join-Path $PSScriptRoot "../../../.."
$ScriptDir = $PSScriptRoot
. (Join-Path $global:VorceRoot "src/lib/utils/StatusPrinter.ps1")
. (Join-Path $global:VorceRoot "src/lib/integrations/GitHubClient.ps1")

# Repository aus Config laden (Mock für Part-Run Test)
$Repo = "Vorce-Studios/Vorce"

$Issues = Get-VorceGitHubIssues -Repository $Repo
Save-VorceGitHubData -Type "issues" -Data $Issues

return @{ 
    count = $Issues.Count 
    timestamp = (Get-Date).ToString("o") 
}
