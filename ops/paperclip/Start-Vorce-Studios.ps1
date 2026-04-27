[CmdletBinding()]
param()
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

if (Test-VorceStudiosPaperclipReady) {
    Set-VorceStudiosRuntimeMode -Mode 'running' -Note 'Manual start (already running).'
    return Get-VorceStudiosRuntimeState
}

$paths = Get-VorceStudiosPaths
$shell = Get-VorceStudiosShellExecutable
$runner = Join-Path $ScriptDir 'Run-Vorce-StudiosPaperclip.ps1'
$stdout = Join-Path $paths.RuntimeLogDir 'paperclip.stdout.log'
$stderr = Join-Path $paths.RuntimeLogDir 'paperclip.stderr.log'

$process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner) -WorkingDirectory $paths.Root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden

$processState = Get-VorceStudiosProcessState
$processState['paperclip'] = @{
    pid = $process.Id
    startedAt = Get-Date -UFormat '%Y-%m-%dT%H:%M:%SZ'
    source = 'manual'
}
Set-VorceStudiosProcessState -State $processState

if (Wait-VorceStudiosPaperclipReady -TimeoutSeconds 60) {
    Set-VorceStudiosRuntimeMode -Mode 'running' -Note 'Manual start success.'
} else {
    throw 'Paperclip start timed out.'
}

Get-VorceStudiosRuntimeState
