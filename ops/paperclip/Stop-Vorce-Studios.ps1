[CmdletBinding()]
param()
<<<<<<< HEAD

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
=======
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
Set-VorceStudiosRuntimeMode -Mode 'stopped' -Note 'Manual stop.'
$server = Get-VorceStudiosServerProcessInfo
if ($server) {
    Stop-Process -Id $server.pid -Force
}
@{ stoppedAt = Get-VorceStudiosTimestamp; mode = 'stopped' }
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
