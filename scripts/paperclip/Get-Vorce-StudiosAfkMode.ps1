[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

$state = Get-VorceStudiosAfkModeState
[pscustomobject]@{
    enabled = [bool]$state.enabled
    preferredApprovalChannel = Get-VorceStudiosPreferredApprovalChannel
    telegramReady = Test-VorceStudiosTelegramTransportReady
    state = $state
}
