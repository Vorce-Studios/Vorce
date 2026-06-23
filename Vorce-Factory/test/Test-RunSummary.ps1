# Test-RunSummary.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$test = New-VorceTestContext -Name 'RunSummary'
$tempVar = Join-Path $projectRoot 'var/tmp/test-run-summary'
if (Test-Path $tempVar) { Remove-Item -LiteralPath $tempVar -Recurse -Force -ErrorAction SilentlyContinue }
$global:VarDir = $tempVar
. (Join-Path $projectRoot 'src/lib/state/StateManager.ps1')

try {
    $historyPath = Join-Path $tempVar 'run-history/MAIN'
    $null = New-Item -ItemType Directory -Path $historyPath -Force
    $sample = [pscustomobject]@{
        schema_version = 2
        id = 'run_test_001'
        main_run_id = 'run_test_001'
        parent_run_id = $null
        name = 'MAIN-RUN-01_Planning'
        type = 'MAIN'
        status = 'completed'
        started_at = (Get-Date).AddMinutes(-5).ToString('o')
        completed_at = (Get-Date).AddMinutes(-1).ToString('o')
        duration_ms = 240000
        input_fingerprint = 'abc'
        metadata = @{}
        results = @(
            [pscustomobject]@{ sub_run = 'DataSync'; status = 'completed'; parts = @([pscustomobject]@{ name='FetchIssues'; status='completed' }) }
        )
    }
    $sample | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $historyPath 'MAIN-RUN-01_Planning_run_test_001.json') -Encoding UTF8

    $summary = Get-VorceRunSummary -Limit 5
    Write-VorceTestResult -Context $test -Message 'Summary-Objekt vorhanden' -Passed ($null -ne $summary)
    Write-VorceTestResult -Context $test -Message 'Recent-Runs enthalten Eintrag' -Passed (@($summary.recent_runs).Count -eq 1)
    Write-VorceTestResult -Context $test -Message 'Summary-Counts vorhanden' -Passed ($summary.recent_runs[0].sub_runs.completed -eq 1)
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if (Test-Path $tempVar) {
        Remove-Item -LiteralPath $tempVar -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
