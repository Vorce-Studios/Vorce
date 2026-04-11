[CmdletBinding()]
param()
<<<<<<< HEAD

=======
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

<<<<<<< HEAD
function Invoke-VorceStudiosRuntimeRepair {
    $repairScript = Join-Path $ScriptDir 'Repair-VorceStudiosPaperclipRuntimes.ps1'
    if (-not (Test-Path -LiteralPath $repairScript)) {
        return @{
            filesChanged = 0
            files = @()
        }
    }

    return & $repairScript
}

function Invoke-VorceStudiosPostStartSync {
    $syncScript = Join-Path $ScriptDir 'Sync-Vorce-StudiosPaperclip.ps1'
    if (-not (Test-Path -LiteralPath $syncScript)) {
        return $null
    }

    try {
        return @{
            ok = $true
            result = (& $syncScript)
            error = $null
        }
    } catch {
        return @{
            ok = $false
            result = $null
            error = $_.Exception.Message
        }
    }
}

$runtimeRepair = Invoke-VorceStudiosRuntimeRepair

if (Test-VorceStudiosPaperclipReady) {
    if ([int]$runtimeRepair.filesChanged -gt 0) {
        $stopScript = Join-Path $ScriptDir 'Stop-Vorce-Studios.ps1'
        if (Test-Path -LiteralPath $stopScript) {
            & $stopScript | Out-Null
        }
    } else {
        $sync = Invoke-VorceStudiosPostStartSync
        $note = if ($null -eq $sync -or $sync.ok) { 'Manual start (already running).' } else { 'Manual start (already running, sync warning).' }
        Set-VorceStudiosRuntimeMode -Mode 'running' -Note $note
        return @{
            runtime = Get-VorceStudiosRuntimeState
            runtimeRepair = $runtimeRepair
            sync = $sync
        }
    }
}

$staleProcesses = @(Get-VorceStudiosPaperclipProcesses)
if (-not (Test-VorceStudiosPaperclipReady) -and $staleProcesses.Count -gt 0) {
    Stop-VorceStudiosPaperclipProcesses | Out-Null
    Start-Sleep -Seconds 1
=======
if (Test-VorceStudiosPaperclipReady) {
    Set-VorceStudiosRuntimeMode -Mode 'running' -Note 'Manual start (already running).'
    return Get-VorceStudiosRuntimeState
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
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
<<<<<<< HEAD
    $sync = Invoke-VorceStudiosPostStartSync
    $note = if ($null -eq $sync -or $sync.ok) { 'Manual start success.' } else { 'Manual start success with sync warning.' }
    Set-VorceStudiosRuntimeMode -Mode 'running' -Note $note
=======
    Set-VorceStudiosRuntimeMode -Mode 'running' -Note 'Manual start success.'
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
} else {
    throw 'Paperclip start timed out.'
}

<<<<<<< HEAD
@{
    runtime = Get-VorceStudiosRuntimeState
    runtimeRepair = $runtimeRepair
    sync = $sync
}
=======
Get-VorceStudiosRuntimeState
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
