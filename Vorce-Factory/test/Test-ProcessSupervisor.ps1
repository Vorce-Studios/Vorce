[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $projectRoot 'src/lib/process/ProcessSupervisor.ps1')

$test = New-VorceTestContext -Name 'ProcessSupervisor'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'vorce-process-supervisor-{0}' -f [guid]::NewGuid().ToString('N')
)
$registryPath = Join-Path $tempRoot 'var/tmp/vorce-processes.json'
$workingDirectory = Join-Path $tempRoot 'workspace'
$commandPath = Join-Path $tempRoot 'bin/fake-process.exe'
$stdoutPath = Join-Path $tempRoot 'logs/stdout.log'
$stderrPath = Join-Path $tempRoot 'logs/stderr.log'
$heartbeatPath = Join-Path $tempRoot 'factory-heartbeat.json'

function Assert-Check {
    param(
        [string]$Message,
        [bool]$Condition
    )

    Write-VorceTestResult -Context $test -Message $Message -Passed $Condition
}

try {
    $null = New-Item -ItemType Directory -Path $workingDirectory -Force
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $commandPath) -Force
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $stdoutPath) -Force
    Set-Content -LiteralPath $commandPath -Value 'fixture' -Encoding UTF8

    $emptyRegistry = New-VorceProcessRegistry
    Write-VorceProcessRegistry -Registry $emptyRegistry -RegistryPath $registryPath | Out-Null
    $readRegistry = Read-VorceProcessRegistry -RegistryPath $registryPath
    Assert-Check 'Atomare Registry ist lesbar' (
        $readRegistry.schema_version -eq 1 -and @($readRegistry.processes).Count -eq 0
    )
    Assert-Check 'Atomarer Write hinterlaesst keine temporaere Datei' (
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $registryPath) -Filter '*.tmp' -File).Count -eq 0
    )

    $record = New-VorceProcessRecord `
        -Component 'fake-dashboard' `
        -ProcessId 424242 `
        -ParentPid $PID `
        -CommandPath $commandPath `
        -WorkingDirectory $workingDirectory `
        -Port 5173 `
        -HealthUrl 'http://127.0.0.1:5173/api/health' `
        -StdoutPath $stdoutPath `
        -StderrPath $stderrPath `
        -SessionId 'test-session'

    Register-VorceProcess -Record $record -RegistryPath $registryPath | Out-Null
    $registered = Read-VorceProcessRegistry -RegistryPath $registryPath
    $registeredRecord = @($registered.processes)[0]
    Assert-Check 'Register speichert alle Pflichtfelder' (
        @($registered.processes).Count -eq 1 -and
        $registeredRecord.component -eq 'fake-dashboard' -and
        [int]$registeredRecord.pid -eq 424242 -and
        $registeredRecord.command_path -eq (ConvertTo-VorceNormalizedPath $commandPath) -and
        $registeredRecord.working_directory -eq (ConvertTo-VorceNormalizedPath $workingDirectory) -and
        $registeredRecord.stdout_path -eq $stdoutPath -and
        $registeredRecord.stderr_path -eq $stderrPath
    )

    $updated = Update-VorceProcess `
        -Component 'fake-dashboard' `
        -Changes @{ status = 'healthy'; health = 'healthy' } `
        -RegistryPath $registryPath
    Assert-Check 'Update aktualisiert Health und Zeitstempel' (
        $updated.status -eq 'healthy' -and
        $updated.health -eq 'healthy' -and
        -not [string]::IsNullOrWhiteSpace([string]$updated.last_health_at)
    )

    $removed = Remove-VorceProcess `
        -Component 'fake-dashboard' `
        -ProcessId 424242 `
        -RegistryPath $registryPath
    $afterRemove = Read-VorceProcessRegistry -RegistryPath $registryPath
    Assert-Check 'Remove entfernt nur den passenden Registry-Eintrag' (
        $removed.component -eq 'fake-dashboard' -and @($afterRemove.processes).Count -eq 0
    )

    $currentProcess = Get-Process -Id $PID
    $currentCommandPath = $currentProcess.Path
    $currentWorkingDirectory = (Get-Location).ProviderPath
    $currentRecord = New-VorceProcessRecord `
        -Component 'current-test-shell' `
        -ProcessId $PID `
        -ParentPid $null `
        -StartedAt $currentProcess.StartTime.ToUniversalTime().ToString('o') `
        -CommandPath $currentCommandPath `
        -WorkingDirectory $currentWorkingDirectory `
        -SessionId 'safe-current-process'
    Register-VorceProcess -Record $currentRecord -RegistryPath $registryPath | Out-Null

    $currentSnapshot = [pscustomobject]@{
        pid = $PID
        exists = $true
        executable_path = $currentCommandPath
        command_line = "`"$currentCommandPath`" -NoProfile"
        working_directory = $currentWorkingDirectory
        parent_pid = $null
        started_at = $currentProcess.StartTime.ToUniversalTime().ToString('o')
    }
    $verifiedIdentity = Test-VorceProcessIdentity `
        -Record $currentRecord `
        -ExpectedCommandPath $currentCommandPath `
        -ExpectedWorkingDirectory $currentWorkingDirectory `
        -ProcessSnapshot $currentSnapshot
    Assert-Check 'PID, CommandPath und WorkingDirectory werden gemeinsam verifiziert' (
        $verifiedIdentity.verified -and $verifiedIdentity.reason -eq 'verified'
    )

    $foreignWorkingDirectory = Join-Path $tempRoot 'foreign-workspace'
    $workingDirectoryStopResult = Stop-VorceRegisteredProcess `
        -Component 'current-test-shell' `
        -ExpectedCommandPath $currentCommandPath `
        -ExpectedWorkingDirectory $foreignWorkingDirectory `
        -RegistryPath $registryPath `
        -Confirm:$false
    Assert-Check 'WorkingDirectory-Mismatch lehnt Stop ab' (
        -not $workingDirectoryStopResult.stopped -and
        $workingDirectoryStopResult.reason -eq 'registry_working_directory_mismatch' -and
        $null -ne (Get-Process -Id $PID -ErrorAction SilentlyContinue)
    )

    $foreignCommandPath = Join-Path $tempRoot 'bin/foreign.exe'
    $stopResult = Stop-VorceRegisteredProcess `
        -Component 'current-test-shell' `
        -ExpectedCommandPath $foreignCommandPath `
        -ExpectedWorkingDirectory $currentWorkingDirectory `
        -RegistryPath $registryPath `
        -Confirm:$false
    $currentStillAlive = $null -ne (Get-Process -Id $PID -ErrorAction SilentlyContinue)
    Assert-Check 'CommandPath-Mismatch lehnt Stop ab' (
        -not $stopResult.stopped -and
        $stopResult.reason -eq 'registry_command_path_mismatch' -and
        $currentStillAlive
    )
    Assert-Check 'Abgelehnter Stop behaelt Registry-Eintrag' (
        @((Read-VorceProcessRegistry -RegistryPath $registryPath).processes).Count -eq 1
    )
    Remove-VorceProcess `
        -Component 'current-test-shell' `
        -ProcessId $PID `
        -RegistryPath $registryPath | Out-Null

    $now = [datetime]'2026-06-23T12:00:00Z'
    @{ timestamp = $now.AddSeconds(-10).ToString('o') } |
        ConvertTo-Json |
        Set-Content -LiteralPath $heartbeatPath -Encoding UTF8
    $healthyHeartbeat = Get-VorceHeartbeatStatus `
        -HeartbeatPath $heartbeatPath `
        -StaleAfterSeconds 60 `
        -Now $now
    Assert-Check 'Aktueller Heartbeat ist healthy' (
        $healthyHeartbeat.status -eq 'healthy' -and $healthyHeartbeat.healthy
    )

    @{ timestamp = $now.AddSeconds(-61).ToString('o') } |
        ConvertTo-Json |
        Set-Content -LiteralPath $heartbeatPath -Encoding UTF8
    $staleHeartbeat = Get-VorceHeartbeatStatus `
        -HeartbeatPath $heartbeatPath `
        -StaleAfterSeconds 60 `
        -Now $now
    Assert-Check 'Alter Heartbeat ist stale' (
        $staleHeartbeat.status -eq 'stale' -and -not $staleHeartbeat.healthy
    )

    $stdoutFixture = @()
    for ($index = 1; $index -le 40; $index++) {
        $stdoutFixture += "stdout-$index"
        if ($index % 4 -eq 0) { $stdoutFixture += '' }
    }
    $stderrFixture = @()
    for ($index = 1; $index -le 35; $index++) {
        $stderrFixture += "stderr-$index"
        if ($index % 3 -eq 0) { $stderrFixture += '   ' }
    }
    Set-Content -LiteralPath $stdoutPath -Value $stdoutFixture -Encoding UTF8
    Set-Content -LiteralPath $stderrPath -Value $stderrFixture -Encoding UTF8

    $crash = Get-VorceCrashExcerpt `
        -ExitCode 23 `
        -StdoutPath $stdoutPath `
        -StderrPath $stderrPath
    Assert-Check 'Crashauszug enthaelt maximal 30/30 nichtleere Zeilen' (
        @($crash.stdout_lines).Count -eq 30 -and
        @($crash.stderr_lines).Count -eq 30 -and
        $crash.terminal_line_count -eq 60 -and
        -not (@($crash.terminal_lines) | Where-Object { [string]::IsNullOrWhiteSpace($_) })
    )
    Assert-Check 'Crashauszug enthaelt jeweils die letzten Zeilen und Pfade' (
        $crash.stdout_lines[0] -eq 'stdout-11' -and
        $crash.stdout_lines[-1] -eq 'stdout-40' -and
        $crash.stderr_lines[0] -eq 'stderr-6' -and
        $crash.stderr_lines[-1] -eq 'stderr-35' -and
        $crash.exit_code -eq 23 -and
        $crash.stdout_path -eq [System.IO.Path]::GetFullPath($stdoutPath) -and
        $crash.stderr_path -eq [System.IO.Path]::GetFullPath($stderrPath)
    )

    $statusRecord = New-VorceProcessRecord `
        -Component 'fake-factory-loop' `
        -ProcessId 987654 `
        -CommandPath $commandPath `
        -WorkingDirectory $workingDirectory `
        -StdoutPath $stdoutPath `
        -StderrPath $stderrPath `
        -Status 'healthy'
    $missingSnapshot = [pscustomobject]@{
        pid = 987654
        exists = $false
        executable_path = $null
        command_line = $null
        working_directory = $null
        parent_pid = $null
        started_at = $null
    }
    $processStatus = Get-VorceProcessStatus `
        -Record $statusRecord `
        -ProcessSnapshot $missingSnapshot
    Assert-Check 'Statusobjekt meldet fehlenden Prozess als stopped' (
        $processStatus.status -eq 'stopped' -and -not $processStatus.healthy
    )
} catch {
    Write-VorceTestResult `
        -Context $test `
        -Message "Unerwartete Ausnahme: $($_.Exception.Message)" `
        -Passed $false
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
