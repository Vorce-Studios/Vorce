# Test-Logging.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

$test = New-VorceTestContext -Name 'Logging'
$global:VorceRoot = $projectRoot
$tempVarDir = Join-Path $projectRoot "var/tmp/test-logging-$PID"
$previousProviderToken = [Environment]::GetEnvironmentVariable('VORCE_TEST_PROVIDER_TOKEN')

if (Test-Path -LiteralPath $tempVarDir) {
    Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
}
$global:VarDir = $tempVarDir
$global:VorceLogContext = $null
$global:VorceStatusRunContexts = @{}

$loggingModule = Join-Path $global:VorceRoot 'src/lib/logging/Write-Log.ps1'
$statusModule = Join-Path $global:VorceRoot 'src/lib/utils/StatusPrinter.ps1'
$logRoot = Join-Path $global:VarDir 'log'
$sessionId = 'test-session-na06'
$sessionLogPath = Join-Path $logRoot "sessions/$sessionId.log"
$errorLogPath = Join-Path $logRoot 'vorce-errors.log'

try {
    $dotSourceOutput = @(. $loggingModule)
    Write-VorceTestResult -Context $test -Message 'Logging-Modul ist ohne Parameter und Ausgabe dot-sourcebar' -Passed ($dotSourceOutput.Count -eq 0)

    $statusDotSourceOutput = @(. $statusModule)
    Write-VorceTestResult -Context $test -Message 'StatusPrinter ist ohne Ausgabe dot-sourcebar' -Passed ($statusDotSourceOutput.Count -eq 0)

    $configDirectory = Join-Path $global:VarDir 'config'
    $null = New-Item -ItemType Directory -Path $configDirectory -Force
    $providerRegistry = @{
        providers = @{
            test_provider = @{
                auth_env_var = 'VORCE_TEST_PROVIDER_TOKEN'
            }
        }
    }
    $providerRegistry | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $configDirectory 'quota-registry.json') -Encoding UTF8

    $messageToken = 'ghp_MessageToken_1234567890'
    $dataToken = 'github_pat_DataToken_1234567890'
    $providerToken = 'provider-secret-value-1234567890'
    [Environment]::SetEnvironmentVariable('VORCE_TEST_PROVIDER_TOKEN', $providerToken)

    $sessionContext = Initialize-VorceLogContext -SessionId $sessionId -Component 'test' -Force
    $mainContext = New-VorceRunContext -RunType MAIN -RunName 'MAIN-RUN-TEST' -ParentContext $sessionContext -RunId 'main-run-na06' -Component 'test'

    $terminalInfo = (& {
        $null = Write-VorceLogEntry `
            -Level INFO `
            -Message "INFO $messageToken VORCE_TEST_PROVIDER_TOKEN=$providerToken" `
            -Component 'test' `
            -EventType 'diagnostic' `
            -Context $mainContext `
            -ProviderRegistry $providerRegistry `
            -Data @{
                nested = @{
                    value = $dataToken
                    provider_value = "prefix-$providerToken-suffix"
                    prompt = 'complete raw prompt must not be logged'
                }
            }
    } 6>&1 | Out-String)
    Write-VorceTestResult -Context $test -Message 'INFO wird am Terminal-Sink ausgegeben' -Passed ($terminalInfo -match '\[INFO\].*\[test\]')

    $terminalError = (& {
        $null = Write-VorceLogEntry `
            -Level ERROR `
            -Message 'ERROR sink test' `
            -Component 'test' `
            -EventType 'diagnostic' `
            -Context $mainContext `
            -Data @{ error_class = 'test_error' } `
            -ErrorClass 'test_error'
    } 6>&1 | Out-String)
    Write-VorceTestResult -Context $test -Message 'ERROR wird am Terminal-Sink ausgegeben' -Passed ($terminalError -match '\[ERROR\].*\[test\]')

    Write-VorceRunStart -RunName 'SUB-RUN-TEST' -Level Sub -SessionId $sessionId -CorrelationId 'main-run-na06' -MainRunId 'main-run-na06' -SubRunId 'sub-run-na06' -Component 'test'
    Write-VorceRunEnd -RunName 'SUB-RUN-TEST' -Level Sub -Status completed -DurationMs 25

    $jobs = @()
    foreach ($jobIndex in 1..3) {
        $jobs += Start-Job -ScriptBlock {
            param($modulePath, $varDir, $sharedSessionId, $sharedRunId, $index)

            $global:VarDir = $varDir
            . $modulePath
            $context = New-VorceRunContext `
                -RunType MAIN `
                -RunName 'PARALLEL-MAIN' `
                -SessionId $sharedSessionId `
                -RunId $sharedRunId `
                -Component 'parallel-test'

            foreach ($eventIndex in 1..20) {
                $null = Write-VorceLogEntry `
                    -Level INFO `
                    -Message "job-$index-event-$eventIndex" `
                    -Component 'parallel-test' `
                    -EventType 'diagnostic' `
                    -Context $context `
                    -Data @{ job = $index; event = $eventIndex } `
                    -SkipTerminal
            }
        } -ArgumentList $loggingModule, $global:VarDir, $sessionId, 'parallel-main-na06', $jobIndex
    }

    $null = $jobs | Wait-Job
    $jobFailures = @($jobs | Where-Object { $_.State -ne 'Completed' })
    $jobErrors = @($jobs | ForEach-Object { @($_.ChildJobs[0].Error) })
    $null = $jobs | Receive-Job
    $jobs | Remove-Job -Force
    Write-VorceTestResult -Context $test -Message 'Drei parallele Logging-Jobs laufen fehlerfrei' -Passed ($jobFailures.Count -eq 0 -and $jobErrors.Count -eq 0)

    $jsonlFile = Get-ChildItem -LiteralPath (Join-Path $logRoot 'events') -Filter 'vorce-events-*.jsonl' -File | Select-Object -First 1
    Write-VorceTestResult -Context $test -Message 'JSONL-Datei wurde erstellt' -Passed ($null -ne $jsonlFile)

    $lines = if ($jsonlFile) {
        @(Get-Content -LiteralPath $jsonlFile.FullName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } else {
        @()
    }
    $parsedEvents = @()
    $parseFailures = @()
    foreach ($line in $lines) {
        try {
            $parsedEvents += $line | ConvertFrom-Json
        } catch {
            $parseFailures += $_
        }
    }
    Write-VorceTestResult -Context $test -Message 'Jede JSONL-Zeile ist einzeln parsebar' -Passed ($lines.Count -gt 0 -and $parseFailures.Count -eq 0 -and $parsedEvents.Count -eq $lines.Count)

    $parallelEvents = @($parsedEvents | Where-Object {
        $_.component -eq 'parallel-test' -and $_.event_type -eq 'diagnostic'
    })
    Write-VorceTestResult -Context $test -Message '3 Jobs x 20 Events sind vollstaendig vorhanden' -Passed ($parallelEvents.Count -eq 60)
    Write-VorceTestResult -Context $test -Message 'Parallele Events behalten dieselbe Run-ID' -Passed (@($parallelEvents.run_id | Select-Object -Unique).Count -eq 1 -and $parallelEvents[0].run_id -eq 'parallel-main-na06')

    $runStartEvents = @($parsedEvents | Where-Object {
        $_.run_name -eq 'SUB-RUN-TEST' -and $_.event_type -eq 'run_started'
    })
    $runEndEvents = @($parsedEvents | Where-Object {
        $_.run_name -eq 'SUB-RUN-TEST' -and $_.event_type -in @('run_completed', 'run_failed')
    })
    $matchingRunIds = $runStartEvents.Count -eq 1 -and
        $runEndEvents.Count -eq 1 -and
        $runStartEvents[0].run_id -eq $runEndEvents[0].run_id -and
        $runStartEvents[0].run_id -eq 'sub-run-na06'
    Write-VorceTestResult -Context $test -Message 'RunStart und genau ein RunEnd verwenden dieselbe Run-ID' -Passed $matchingRunIds

    $sessionText = if (Test-Path -LiteralPath $sessionLogPath) {
        Get-Content -LiteralPath $sessionLogPath -Raw
    } else {
        ''
    }
    $errorText = if (Test-Path -LiteralPath $errorLogPath) {
        Get-Content -LiteralPath $errorLogPath -Raw
    } else {
        ''
    }
    $jsonlText = if ($jsonlFile) {
        Get-Content -LiteralPath $jsonlFile.FullName -Raw
    } else {
        ''
    }
    $allSinkText = "$sessionText`n$errorText`n$jsonlText"

    Write-VorceTestResult -Context $test -Message 'INFO und ERROR stehen im Session-Sink' -Passed ($sessionText -match '\[INFO\]' -and $sessionText -match '\[ERROR\]')
    Write-VorceTestResult -Context $test -Message 'ERROR steht im Fehler-Sink' -Passed ($errorText -match '\[ERROR\].*ERROR sink test')
    Write-VorceTestResult -Context $test -Message 'INFO und ERROR stehen im JSONL-Sink' -Passed (@($parsedEvents | Where-Object level -eq 'INFO').Count -gt 0 -and @($parsedEvents | Where-Object level -eq 'ERROR').Count -gt 0)
    Write-VorceTestResult -Context $test -Message 'Fake-Token aus Message und Data sind in keinem Dateisink enthalten' -Passed (
        $allSinkText -notmatch [regex]::Escape($messageToken) -and
        $allSinkText -notmatch [regex]::Escape($dataToken) -and
        $allSinkText -notmatch [regex]::Escape($providerToken)
    )

    $redactedEvent = $parsedEvents | Where-Object { $_.message -match '^INFO ' } | Select-Object -First 1
    $recursiveRedactionPassed = $redactedEvent -and
        $redactedEvent.message -match '\[REDACTED\]' -and
        $redactedEvent.data.nested.value -eq '[REDACTED]' -and
        $redactedEvent.data.nested.provider_value -match '\[REDACTED\]' -and
        $redactedEvent.data.nested.prompt -eq '[OMITTED]'
    Write-VorceTestResult -Context $test -Message 'Message, verschachtelte Data und Promptfelder werden redigiert' -Passed $recursiveRedactionPassed
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    [Environment]::SetEnvironmentVariable('VORCE_TEST_PROVIDER_TOKEN', $previousProviderToken)
    Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Job*' } | Remove-Job -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempVarDir) {
        Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
