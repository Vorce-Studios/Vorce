Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
<<<<<<< HEAD
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')

function Ensure-VorceStudiosWorktreeConfig {
    $paths = Get-VorceStudiosPaths
    $system = Get-VorceStudiosSystemPolicy
    if ((Test-Path -LiteralPath $paths.PaperclipConfigPath) -and (Test-Path -LiteralPath $paths.PaperclipEnvPath)) {
        return
    }

    $cli = Get-VorceStudiosPaperclipCli
    & $cli.FilePath @(
        $cli.Arguments +
        @(
            'worktree',
            'init',
            '--name', $system.Company.Name,
            '--instance', $system.Company.InstanceId,
            '--home', $paths.PaperclipHome,
            '--server-port', [string]$system.Company.ServerPort,
            '--db-port', [string]$system.Company.DatabasePort,
            '--no-seed',
            '--force'
        )
    )

    if ($LASTEXITCODE -ne 0) {
        throw 'Paperclip worktree init ist fehlgeschlagen.'
    }

    Sync-VorceStudiosWorktreeConfigFile | Out-Null
}
=======
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))

$paths = Get-VorceStudiosPaths
$system = Get-VorceStudiosSystemPolicy
$cli = Get-VorceStudiosPaperclipCli

Ensure-VorceStudiosRuntimeDirectories
<<<<<<< HEAD
Ensure-VorceStudiosWorktreeConfig
Sync-VorceStudiosWorktreeConfigFile | Out-Null
=======
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
Import-VorceStudiosPaperclipEnvironment
Ensure-VorceStudiosPaperclipPluginLoaderPatched | Out-Null

$env:PAPERCLIP_HOME = $paths.PaperclipHome
$env:PAPERCLIP_CONFIG = $paths.PaperclipConfigPath
$env:PAPERCLIP_INSTANCE_ID = $system.Company.InstanceId
<<<<<<< HEAD
$env:HOST = '127.0.0.1'
$env:PAPERCLIP_LISTEN_HOST = '127.0.0.1'
$env:PAPERCLIP_LISTEN_PORT = [string]$system.Company.ServerPort
$env:PORT = [string]$system.Company.ServerPort
$env:PAPERCLIP_API_URL = ('http://127.0.0.1:{0}' -f $system.Company.ServerPort)
=======
$env:HOST = '0.0.0.0'
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
$env:PAPERCLIP_DISABLE_SKILL_LINKING = 'true'

Set-Location $paths.Root
& $cli.FilePath @($cli.Arguments + @('run', '-c', $paths.PaperclipConfigPath, '-d', $paths.PaperclipHome))
exit $LASTEXITCODE
