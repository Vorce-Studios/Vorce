# PART-RUN-02_FetchPRs.ps1 (Vorce 3.0)
[CmdletBinding()]
param([Parameter(Mandatory)][hashtable]$ConfigBag)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "integrations/GitHubClient.ps1")

# Repository aus Config laden (Mock für Part-Run Test)
$Repo = $ConfigBag.Config.repository

$PRs = Get-VorceGitHubPRs -Repository $Repo
Save-VorceGitHubData -Type "prs" -Data $PRs

return @{
    count = $PRs.Count
    timestamp = (Get-Date).ToString("o")
}
