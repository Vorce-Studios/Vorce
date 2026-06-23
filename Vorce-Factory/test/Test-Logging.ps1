# Test-Logging.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

$test = New-VorceTestContext -Name 'Logging'
$global:VorceRoot = $projectRoot
$tempVarDir = Join-Path $projectRoot 'var/tmp/test-logging'
if (Test-Path $tempVarDir) {
    Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
}
$global:VarDir = $tempVarDir
. (Join-Path $global:VorceRoot 'src/lib/logging/Write-Log.ps1')

$logRoot = Join-Path $global:VarDir 'log'
$sessionLogPath = Join-Path $logRoot 'sessions/test-session.log'
$errorLogPath = Join-Path $logRoot 'vorce-errors.log'

try {
    $entry = Write-VorceLogEntry -Level INFO -Message 'Logging-Test' -Component 'test' -SessionId 'test-session' -EventType 'diagnostic' -ProcessId $PID
    Write-VorceTestResult -Context $test -Message 'Write-VorceLogEntry gibt Struktur zurück' -Passed ($null -ne $entry -and $entry.level -eq 'INFO' -and $entry.component -eq 'test')

    Write-VorceTestResult -Context $test -Message 'Session-Log erstellt' -Passed (Test-Path $sessionLogPath)
    Write-VorceTestResult -Context $test -Message 'JSONL-Verzeichnis erstellt' -Passed (Test-Path (Join-Path $logRoot 'events'))
    Write-VorceTestResult -Context $test -Message 'Fehlerlog-Verzeichnis erstellt' -Passed (Test-Path (Split-Path -Parent $errorLogPath))

    $jsonlFile = Get-ChildItem -LiteralPath (Join-Path $logRoot 'events') -Filter 'vorce-events-*.jsonl' -File | Select-Object -First 1
    if ($jsonlFile) {
        try {
            $line = Get-Content -LiteralPath $jsonlFile.FullName -Raw
            $parsed = $line.Trim().Split("`n") | Select-Object -First 1 | ConvertFrom-Json
            Write-VorceTestResult -Context $test -Message 'JSONL-Zeile parsebar' -Passed ($parsed.message -eq 'Logging-Test')
        } catch {
            Write-VorceTestResult -Context $test -Message 'JSONL-Zeile parsebar' -Passed $false
        }
    } else {
        Write-VorceTestResult -Context $test -Message 'JSONL-Datei vorhanden' -Passed $false
    }
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if (Test-Path $tempVarDir) {
        Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
