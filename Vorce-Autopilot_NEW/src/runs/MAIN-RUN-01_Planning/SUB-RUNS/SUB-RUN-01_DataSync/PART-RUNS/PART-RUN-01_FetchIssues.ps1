# PART-RUN-01_FetchIssues.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "../../../lib/StatusPrinter.ps1")
. (Join-Path $ScriptDir "../../../lib/GitHubClient.ps1")

# Repository aus Config laden (Mock für Part-Run Test)
$Repo = "Vorce-Studios/Vorce"

$Issues = Get-VorceGitHubIssues -Repository $Repo
Save-VorceGitHubData -Type "issues" -Data $Issues

return @{ 
    count = $Issues.Count 
    timestamp = (Get-Date).ToString("o") 
}
