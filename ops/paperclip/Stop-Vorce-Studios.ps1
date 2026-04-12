[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')

Set-VorceStudiosRuntimeMode -Mode 'stopped' -Note 'Manual stop.'

$terminated = Stop-VorceStudiosPaperclipProcesses
$processState = Get-VorceStudiosProcessState
$processState['paperclip'] = $null
$processState['supervisor'] = $null
Set-VorceStudiosProcessState -State $processState

@{
    stoppedAt = Get-VorceStudiosTimestamp
    mode = 'stopped'
    terminated = $terminated
}
