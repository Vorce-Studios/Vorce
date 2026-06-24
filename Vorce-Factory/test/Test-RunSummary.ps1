# Test-RunSummary.ps1
[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$test = New-VorceTestContext -Name 'RunSummary'
$tempVar = Join-Path ([System.IO.Path]::GetTempPath()) ("vorce-run-summary-" + [guid]::NewGuid().ToString('N'))
$global:VarDir = $tempVar
. (Join-Path $projectRoot 'src/lib/state/StateManager.ps1')

function Write-SummaryFixture {
    param([Parameter(Mandatory)][object]$State)
    $path = Get-VorceRunHistoryPath -State $State
    Ensure-VorceParentDirectory -Path $path
    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
}

try {
    $now = Get-Date
    $completed = [pscustomobject]@{
        schema_version = 2
        id = 'run_completed'
        main_run_id = 'run_completed'
        parent_run_id = $null
        name = 'MAIN-RUN-01_Planning'
        type = 'MAIN'
        status = 'completed'
        started_at = $now.AddMinutes(-5).ToString('o')
        completed_at = $now.AddMinutes(-4).ToString('o')
        duration_ms = 1000
        metadata = @{ resume_count = 1; result_summary = ('x' * 220) }
        results = @(
            [pscustomobject]@{
                sub_run = 'Strategy'
                status = 'completed'
                parts = @(
                    [pscustomobject]@{
                        name = 'CreateProposal'
                        status = 'completed'
                        attempts = @(
                            [pscustomobject]@{ attempt_id = 'a1'; provider = 'first'; error_class = 'timeout'; estimated_cost_usd = 0.1; input_tokens = 10; output_tokens = 2 },
                            [pscustomobject]@{ attempt_id = 'a2'; provider = 'second'; status = 'succeeded'; estimated_cost_usd = 0.2; input_tokens = 20; output_tokens = 4 }
                        )
                    },
                    [pscustomobject]@{ name = 'Reuse'; status = 'reused'; attempts = @() },
                    [pscustomobject]@{ name = 'NoWork'; status = 'no_work'; attempts = @() }
                )
            }
        )
    }
    Write-SummaryFixture -State $completed

    $failed = [pscustomobject]@{
        schema_version = 2
        id = 'run_failed'
        main_run_id = 'run_failed'
        parent_run_id = $null
        name = 'MAIN-RUN-03_Audit'
        type = 'MAIN'
        status = 'failed'
        started_at = $now.AddHours(-2).ToString('o')
        completed_at = $now.AddHours(-1).ToString('o')
        duration_ms = 2000
        error = 'Audit failed'
        metadata = @{}
        results = @(
            [pscustomobject]@{
                sub_run = 'Compliance'
                status = 'failed'
                error = 'Compliance failed'
                parts = @(
                    [pscustomobject]@{
                        name = 'Check'
                        status = 'failed'
                        error_class = 'auth_missing'
                        attempts = @([pscustomobject]@{ attempt_id = 'a3'; provider = 'third'; error_class = 'auth_missing' })
                    }
                )
            }
        )
    }
    Write-SummaryFixture -State $failed

    $waiting = [pscustomobject]@{
        schema_version = 2
        id = 'run_waiting'
        main_run_id = 'run_waiting'
        parent_run_id = $null
        name = 'MAIN-RUN-04_Optimizer'
        type = 'MAIN'
        status = 'waiting_provider'
        started_at = $now.AddMinutes(-1).ToString('o')
        completed_at = $null
        duration_ms = 3000
        metadata = @{}
        results = @(
            [pscustomobject]@{
                sub_run = 'Analysis'
                status = 'waiting_provider'
                parts = @(
                    [pscustomobject]@{
                        name = 'Analyze'
                        status = 'waiting_provider'
                        attempts = @([pscustomobject]@{ attempt_id = 'a4'; provider = 'fourth'; error_class = 'quota_exhausted' })
                    }
                )
            }
        )
    }
    Write-SummaryFixture -State $waiting

    $old = [pscustomobject]@{
        schema_version = 2
        id = 'run_old'
        main_run_id = 'run_old'
        parent_run_id = $null
        name = 'MAIN-RUN-05_MemoryOptimization'
        type = 'MAIN'
        status = 'completed'
        started_at = $now.AddDays(-9).ToString('o')
        completed_at = $now.AddDays(-8).ToString('o')
        duration_ms = 9999
        metadata = @{}
        results = @()
    }
    Write-SummaryFixture -State $old

    $summary = Get-VorceRunSummary -Limit 3
    $recentCompleted = @($summary.recent_runs | Where-Object { $_.run_id -eq 'run_completed' })[0]
    Write-VorceTestResult -Context $test -Message 'Limit begrenzt Recent-Runs' -Passed (@($summary.recent_runs).Count -eq 3)
    Write-VorceTestResult -Context $test -Message 'Provider-Attempts und Fallback werden echt aggregiert' -Passed ($recentCompleted.provider_attempts -eq 2 -and $recentCompleted.fallbacks -eq 1)
    Write-VorceTestResult -Context $test -Message 'Tokens und Kosten werden echt aggregiert' -Passed ($recentCompleted.input_tokens -eq 30 -and $recentCompleted.output_tokens -eq 6 -and [math]::Abs($recentCompleted.estimated_cost_usd - 0.3) -lt 0.0001)
    Write-VorceTestResult -Context $test -Message 'Resume, reused und no_work werden sichtbar' -Passed ($recentCompleted.resume_count -eq 1 -and $recentCompleted.part_runs.reused -eq 1 -and $recentCompleted.no_work -eq 1)
    Write-VorceTestResult -Context $test -Message 'Result-Summary ist maximal 160 Zeichen' -Passed ($recentCompleted.result_summary.Length -eq 160)
    Write-VorceTestResult -Context $test -Message 'PrimaryError stammt aus strukturiertem Fehlerfeld' -Passed ((@($summary.recent_runs | Where-Object { $_.run_id -eq 'run_failed' })[0].primary_error) -eq 'Audit failed')
    Write-VorceTestResult -Context $test -Message '24h-Statuswerte enthalten completed, failed und waiting_provider' -Passed ($summary.stats_24h.runs_started -eq 3 -and $summary.stats_24h.runs_completed -eq 1 -and $summary.stats_24h.runs_failed -eq 1 -and $summary.stats_24h.runs_waiting_provider -eq 1)
    Write-VorceTestResult -Context $test -Message '24h-Fehlerklassen werden strukturiert gezaehlt' -Passed ($summary.stats_24h.timeout_errors -eq 1 -and $summary.stats_24h.auth_errors -eq 1 -and $summary.stats_24h.rate_limit_errors -eq 1)
    Write-VorceTestResult -Context $test -Message 'P95 ist fuer deterministische Dauerwerte korrekt' -Passed ($summary.stats_24h.p95_duration_ms -eq 3000)
    Write-VorceTestResult -Context $test -Message '7d-Fenster schliesst alten Run aus' -Passed ($summary.stats_7d.runs_started -eq 3)
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if (Test-Path $tempVar) {
        Remove-Item -LiteralPath $tempVar -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
