Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')

$paths = Get-VorceStudiosPaths
$system = Get-VorceStudiosSystemPolicy
$cli = Get-VorceStudiosPaperclipCli

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment
Ensure-VorceStudiosPaperclipPluginLoaderPatched | Out-Null

$env:PAPERCLIP_HOME = $paths.PaperclipHome
$env:PAPERCLIP_CONFIG = $paths.PaperclipConfigPath
$env:PAPERCLIP_INSTANCE_ID = $system.Company.InstanceId
$env:HOST = '127.0.0.1'
$env:PAPERCLIP_DISABLE_SKILL_LINKING = 'true'

Set-Location $paths.Root
& $cli.FilePath @($cli.Arguments + @('run', '-c', $paths.PaperclipConfigPath, '-d', $paths.PaperclipHome))
exit $LASTEXITCODE
