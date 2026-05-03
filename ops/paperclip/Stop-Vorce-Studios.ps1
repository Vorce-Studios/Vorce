[CmdletBinding()]
param()
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
Set-VorceStudiosRuntimeMode -Mode 'stopped' -Note 'Manual stop.'
$server = Get-VorceStudiosServerProcessInfo
if ($server) {
    Stop-Process -Id $server.pid -Force
}
@{ stoppedAt = Get-VorceStudiosTimestamp; mode = 'stopped' }
