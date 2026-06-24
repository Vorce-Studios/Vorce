[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $projectRoot 'src/lib/maintenance/RetentionManager.ps1')

$test = New-VorceTestContext -Name 'Retention'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'vorce-retention-{0}' -f [guid]::NewGuid().ToString('N')
)
$varRoot = Join-Path $tempRoot 'var'
$outsideRoot = Join-Path $tempRoot 'outside'
$now = [datetime]'2026-06-23T12:00:00Z'
$openStream = $null
$junctionPath = $null

function New-TestFile {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [string]$Content = 'fixture',
        [datetime]$LastWrite = $now
    )

    $path = Join-Path $varRoot $RelativePath
    $parent = Split-Path -Parent $path
    $null = New-Item -ItemType Directory -Path $parent -Force
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    (Get-Item -LiteralPath $path).LastWriteTimeUtc = $LastWrite.ToUniversalTime()
    return $path
}

function Test-Check {
    param([string]$Message, [bool]$Condition)
    Write-VorceTestResult -Context $test -Message $Message -Passed $Condition
}

try {
    $null = New-Item -ItemType Directory -Path $varRoot -Force
    $null = New-Item -ItemType Directory -Path $outsideRoot -Force

    $dryRunFile = New-TestFile -RelativePath 'tmp/dry-run.txt' -LastWrite $now.AddDays(-2)
    $dryRunReport = Invoke-VorceRetention -VarRoot $varRoot -Now $now -Confirm:$false
    Test-Check 'DryRun ist standardmaessig aktiv' $dryRunReport.dry_run
    Test-Check 'DryRun veraendert keine Datei' (Test-Path -LiteralPath $dryRunFile)
    Test-Check 'DryRun meldet geplante Aktionen strukturiert' (
        $dryRunReport.totals.planned -gt 0 -and $dryRunReport.schema_version -eq 1
    )

    $oldEvent = New-TestFile -RelativePath 'log/events/vorce-events-20260501.jsonl' `
        -Content '{"old":true}' -LastWrite $now.AddDays(-31)
    $gzipEvent = New-TestFile -RelativePath 'log/events/vorce-events-20260620.jsonl' `
        -Content ('{"compress":true}' * 20) -LastWrite $now.AddDays(-3)
    $newEvent = New-TestFile -RelativePath 'log/events/vorce-events-20260623.jsonl' `
        -Content '{"new":true}' -LastWrite $now.AddHours(-1)

    foreach ($index in 1..31) {
        $sessionPath = New-TestFile -RelativePath ("log/sessions/session-{0:D2}.log" -f $index) `
            -LastWrite $now.AddMinutes(-$index)
        if ($index -eq 31) {
            $activeSessionPath = $sessionPath
        }
    }
    $oldSession = New-TestFile -RelativePath 'log/sessions/expired.log' -LastWrite $now.AddDays(-31)

    $errorLog = New-TestFile -RelativePath 'log/vorce-errors.log' -Content ('x' * 2048)
    foreach ($index in 1..4) {
        $null = New-TestFile -RelativePath "log/vorce-errors.log.$index" -Content "generation-$index"
    }

    $oldProcessLog = New-TestFile -RelativePath 'log/process/old/stdout.log' -LastWrite $now.AddDays(-15)
    $activeProcessLog = New-TestFile -RelativePath 'log/process/active/stderr.log' -LastWrite $now.AddDays(-15)
    $openLog = New-TestFile -RelativePath 'log/process/open/stdout.log' -LastWrite $now.AddDays(-15)
    $openStream = New-Object System.IO.FileStream(
        $openLog,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::None
    )

    $registryPath = New-TestFile -RelativePath 'tmp/vorce-processes.json' -Content (@{
        schema_version = 1
        processes = @(
            @{
                component = 'fixture'
                pid = $PID
                stdout_path = $null
                stderr_path = $activeProcessLog
                session_id = 'session-31'
            }
        )
    } | ConvertTo-Json -Depth 5)

    $successfulArtifact = New-TestFile `
        -RelativePath 'tmp/agent-artifacts/main/part/success-attempt/stdout.log' `
        -LastWrite $now.AddHours(-25)
    $failedRecentArtifact = New-TestFile `
        -RelativePath 'tmp/agent-artifacts/main/part/failed-recent/stderr.log' `
        -LastWrite $now.AddDays(-6)
    $failedOldArtifact = New-TestFile `
        -RelativePath 'tmp/agent-artifacts/main/part/failed-old/stderr.log' `
        -LastWrite $now.AddDays(-8)
    $historyState = New-TestFile -RelativePath 'run-history/MAIN/Test/history.json' -Content (@{
        status = 'completed'
        attempts = @(
            @{ attempt_id = 'success-attempt'; success = $true; status = 'completed' },
            @{ attempt_id = 'failed-recent'; success = $false; status = 'failed' },
            @{ attempt_id = 'failed-old'; success = $false; status = 'failed' }
        )
    } | ConvertTo-Json -Depth 5) -LastWrite $now.AddDays(-100)

    $archive = New-TestFile -RelativePath 'run-states-archive/old.json' -LastWrite $now.AddDays(-91)
    $reportFile = New-TestFile -RelativePath 'analysis/old-report.json' -LastWrite $now.AddDays(-31)
    $currentConfig = New-TestFile -RelativePath 'config/app.json' -Content '{}'
    foreach ($index in 1..22) {
        $null = New-TestFile -RelativePath ("config/app.json.bak.{0:D2}" -f $index) `
            -LastWrite $now.AddMinutes(-$index)
    }

    $outsideFile = Join-Path $outsideRoot 'must-stay.txt'
    Set-Content -LiteralPath $outsideFile -Value 'outside' -Encoding UTF8
    $policy = New-VorceRetentionPolicy
    $policy.error_log.max_size_bytes = 1024
    $policy.error_log.generations = 3
    $policy.reports.roots = @('analysis', '../outside')

    $junctionTarget = Join-Path $outsideRoot 'junction-target'
    $null = New-Item -ItemType Directory -Path $junctionTarget -Force
    Set-Content -LiteralPath (Join-Path $junctionTarget 'outside-old.txt') -Value 'outside' -Encoding UTF8
    try {
        $junctionPath = Join-Path $varRoot 'tmp/outside-junction'
        $null = New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget -ErrorAction Stop
    } catch {
        $junctionPath = $null
    }

    $report = Invoke-VorceRetention -VarRoot $varRoot -RegistryPath $registryPath `
        -Policy $policy -Now $now -DryRun:$false -Confirm:$false

    Test-Check 'Altes JSONL wird geloescht' (-not (Test-Path -LiteralPath $oldEvent))
    Test-Check 'JSONL ab zwei Tagen wird gzip-komprimiert' (
        -not (Test-Path -LiteralPath $gzipEvent) -and
        (Test-Path -LiteralPath "$gzipEvent.gz")
    )
    Test-Check 'Neues JSONL bleibt erhalten' (Test-Path -LiteralPath $newEvent)
    Test-Check 'Aktive Session bleibt trotz Dateilimit erhalten' (Test-Path -LiteralPath $activeSessionPath)
    Test-Check 'Abgelaufene Session wird geloescht' (-not (Test-Path -LiteralPath $oldSession))
    Test-Check 'Session-Retention begrenzt nichtaktive Dateien und behaelt aktive zusaetzlich' (
        @(Get-ChildItem -LiteralPath (Join-Path $varRoot 'log/sessions') -Filter '*.log' -File |
            Where-Object { $_.FullName -ne $activeSessionPath }).Count -le 30
    )

    Test-Check 'Fehlerlog wird groessenbasiert rotiert' (
        (Test-Path -LiteralPath $errorLog) -and
        (Get-Item -LiteralPath $errorLog).Length -eq 0 -and
        (Test-Path -LiteralPath "$errorLog.1")
    )
    $errorGenerationFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $errorLog) `
        -Filter 'vorce-errors.log*' -File | Where-Object { $_.Name -match '^vorce-errors\.log\.\d+$' })
    Test-Check 'Fehlerlog behaelt maximal konfigurierte Generationen' (
        $errorGenerationFiles.Count -gt 0 -and $errorGenerationFiles.Count -le 3
    )

    Test-Check 'Alter inaktiver Prozesslog wird geloescht' (-not (Test-Path -LiteralPath $oldProcessLog))
    Test-Check 'Registry-Prozesslog bleibt geschuetzt' (Test-Path -LiteralPath $activeProcessLog)
    Test-Check 'Offener Prozesslog bleibt geschuetzt' (Test-Path -LiteralPath $openLog)
    Test-Check 'Prozessregistry selbst bleibt geschuetzt' (Test-Path -LiteralPath $registryPath)

    Test-Check 'Erfolgreiches Attempt-Artefakt nutzt 24h-Retention' (
        -not (Test-Path -LiteralPath (Split-Path -Parent $successfulArtifact))
    )
    Test-Check 'Fehlgeschlagenes Attempt-Artefakt bleibt sieben Tage' (
        Test-Path -LiteralPath $failedRecentArtifact
    )
    Test-Check 'Altes fehlgeschlagenes Attempt-Artefakt wird geloescht' (
        -not (Test-Path -LiteralPath (Split-Path -Parent $failedOldArtifact))
    )

    Test-Check 'Archiv und Report folgen ihrer Policy' (
        -not (Test-Path -LiteralPath $archive) -and
        -not (Test-Path -LiteralPath $reportFile)
    )
    Test-Check 'Run-History bleibt durch Default-Policy unangetastet' (Test-Path -LiteralPath $historyState)
    Test-Check 'Aktuelle Config bleibt erhalten' (Test-Path -LiteralPath $currentConfig)
    Test-Check 'Config-Backups werden auf die letzten 20 begrenzt' (
        @(Get-ChildItem -LiteralPath (Join-Path $varRoot 'config') -Filter '*.bak.*' -File).Count -eq 20
    )
    Test-Check 'Policy-Root ausserhalb VarDir wird abgelehnt' (
        (Test-Path -LiteralPath $outsideFile) -and $report.totals.rejected -gt 0
    )
    if ($junctionPath) {
        Test-Check 'Junction wird nicht traversiert oder geloescht' (
            (Test-Path -LiteralPath $junctionPath) -and
            (Test-Path -LiteralPath (Join-Path $junctionTarget 'outside-old.txt'))
        )
    } else {
        Test-Check 'Reparse-Test ist auf diesem Host nicht erstellbar' $true
    }
    Test-Check 'Structured Report aggregiert ohne Dateiliste' (
        $report.status -eq 'completed_with_warnings' -and
        @($report.categories).Count -ge 10 -and
        $report.totals.deleted -gt 0 -and
        $report.PSObject.Properties.Name -notcontains 'deleted_paths'
    )

    $brokenRegistry = New-TestFile -RelativePath 'tmp/broken-registry.json' -Content '{broken'
    $blockedCandidate = New-TestFile -RelativePath 'tmp/blocked.txt' -LastWrite $now.AddDays(-2)
    $blockedReport = Invoke-VorceRetention -VarRoot $varRoot -RegistryPath $brokenRegistry `
        -Now $now -DryRun:$false -Confirm:$false
    Test-Check 'Unlesbare Registry blockiert Cleanup fail-closed' (
        $blockedReport.status -eq 'safety_blocked' -and
        (Test-Path -LiteralPath $blockedCandidate)
    )
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if ($openStream) {
        $openStream.Dispose()
    }
    if ($junctionPath -and (Test-Path -LiteralPath $junctionPath)) {
        try {
            [System.IO.Directory]::Delete($junctionPath, $false)
        } catch {
        }
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
