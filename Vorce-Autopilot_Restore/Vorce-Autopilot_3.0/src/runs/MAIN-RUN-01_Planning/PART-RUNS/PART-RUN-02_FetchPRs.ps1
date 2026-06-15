# PART-RUN-02_FetchPRs.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "../../../lib/StatusPrinter.ps1")
. (Join-Path $ScriptDir "../../../lib/GitHubClient.ps1")

# Repository aus Config laden (Mock für Part-Run Test)
$Repo = "Vorce-Studios/Vorce"

$PRs = Get-VorceGitHubPRs -Repository $Repo
Save-VorceGitHubData -Type "prs" -Data $PRs

return @{
    count = $PRs.Count
    timestamp = (Get-Date).ToString("o")
}
