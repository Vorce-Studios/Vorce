[CmdletBinding()]
param(
    [string]$UpdatedBy = 'manual'
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

$state = Disable-VorceStudiosAfkModeState -UpdatedBy $UpdatedBy

[pscustomobject]@{
    enabled = $false
    preferredApprovalChannel = Get-VorceStudiosPreferredApprovalChannel
    state = $state
}
