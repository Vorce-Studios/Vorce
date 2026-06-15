# PART-RUN-01_FetchIssues.ps1 (Vorce 3.0)
[CmdletBinding()]
param([Parameter(Mandatory)][hashtable]$ConfigBag)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "integrations/GitHubClient.ps1")

# Repository aus Config laden (Mock für Part-Run Test)
$Repo = $ConfigBag.Config.repository

$Issues = Get-VorceGitHubIssues -Repository $Repo
Save-VorceGitHubData -Type "issues" -Data $Issues

return @{ 
    count = $Issues.Count 
    timestamp = (Get-Date).ToString("o") 
}
