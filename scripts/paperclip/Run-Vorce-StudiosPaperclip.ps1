[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')

$paths = Get-VorceStudiosPaths
$system = Get-VorceStudiosSystemPolicy
$cli = Get-VorceStudiosPaperclipCli

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment
Ensure-VorceStudiosPaperclipPluginLoaderPatched | Out-Null

$nodeCommand = Get-Command 'node.exe' -ErrorAction SilentlyContinue
if ($null -eq $nodeCommand) {
    $nodeCommand = Get-Command 'node' -ErrorAction SilentlyContinue
}
if ($null -ne $nodeCommand) {
    $nodeDir = Split-Path -Parent $nodeCommand.Source
    if ($env:Path -notlike "*$nodeDir*") {
        $env:Path = '{0};{1}' -f $nodeDir, $env:Path
    }
}

$env:PAPERCLIP_HOME = $paths.PaperclipHome
$env:PAPERCLIP_CONFIG = $paths.PaperclipConfigPath
$env:PAPERCLIP_INSTANCE_ID = $system.Company.InstanceId

if (-not $system.Runtime.NativeHeartbeatScheduler) {
    $env:HEARTBEAT_SCHEDULER_ENABLED = 'false'
}

Set-Location $paths.Root
& $cli.FilePath @($cli.Arguments + @('run', '-c', $paths.PaperclipConfigPath, '-d', $paths.PaperclipHome))
exit $LASTEXITCODE
