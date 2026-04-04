[CmdletBinding()]
param(
    [int]$Top = 15
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\GitHubOrchestrationSync.ps1')

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

$repository = Get-VorceStudiosRepositorySlug
$records = @(Invoke-VorceStudiosPlanningSweep -Repository $repository)

[pscustomobject]@{
    repository = $repository
    updatedAt = (Get-VorceStudiosPlanningSnapshot).updatedAt
    topItems = @($records | Select-Object -First $Top)
    buckets = @{
        critical = (@($records | Where-Object { [string]$_.bucket -eq 'critical' })).Count
        high = (@($records | Where-Object { [string]$_.bucket -eq 'high' })).Count
        medium = (@($records | Where-Object { [string]$_.bucket -eq 'medium' })).Count
        low = (@($records | Where-Object { [string]$_.bucket -eq 'low' })).Count
    }
}
