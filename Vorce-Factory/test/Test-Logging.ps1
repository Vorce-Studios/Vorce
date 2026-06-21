# Test-Logging.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$passCount = 0
$totalChecks = 0

function Write-TestResult {
    param([string]$Message, [bool]$Passed)
    $status = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    Write-Host "$status $Message"
    if ($Passed) { $script:passCount++ }
    $script:totalChecks++
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$global:VorceRoot = $projectRoot
$global:VarDir = Join-Path $projectRoot 'var'
. (Join-Path $global:VorceRoot 'src/lib/logging/Write-Log.ps1')

$logRoot = Join-Path $global:VarDir 'log'
if (Test-Path $logRoot) {
    Remove-Item -LiteralPath $logRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$entry = Write-VorceLogEntry -Level INFO -Message 'Logging-Test' -Component 'test' -SessionId 'test-session' -EventType 'diagnostic' -ProcessId $PID
Write-TestResult 'Write-VorceLogEntry gibt Struktur zurück' ($null -ne $entry -and $entry.level -eq 'INFO' -and $entry.component -eq 'test')

$sessionLogPath = Join-Path $logRoot 'sessions/test-session.log'
$errorLogPath = Join-Path $logRoot 'vorce-errors.log'

Write-TestResult 'Session-Log erstellt' (Test-Path $sessionLogPath)
Write-TestResult 'JSONL-Verzeichnis erstellt' (Test-Path (Join-Path $logRoot 'events'))
Write-TestResult 'Fehlerlog-Verzeichnis erstellt' (Test-Path (Split-Path -Parent $errorLogPath))

$jsonlFile = Get-ChildItem -LiteralPath (Join-Path $logRoot 'events') -Filter 'vorce-events-*.jsonl' -File | Select-Object -First 1
if ($jsonlFile) {
    try {
        $line = Get-Content -LiteralPath $jsonlFile.FullName -Raw
        $parsed = $line.Trim().Split("`n") | Select-Object -First 1 | ConvertFrom-Json
        Write-TestResult 'JSONL-Zeile parsebar' ($parsed.message -eq 'Logging-Test')
    } catch {
        Write-TestResult 'JSONL-Zeile parsebar' $false
    }
} else {
    Write-TestResult 'JSONL-Datei vorhanden' $false
}

Write-Host "`nErgebnis: $passCount/$totalChecks Checks bestanden"
