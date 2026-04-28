[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int[]]$IssueNumbers = @(371, 370, 369, 368, 367),
    [string]$Repository = "Vorce-Studios/Vorce",
    [switch]$AutoCreatePr,
    [int]$MaxConcurrent = 10,
    [int]$RateLimitDelayMs = 800
)

Set-StrictMode -Version 1.0
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

if ($env:JULES_MAX_CONCURRENT_SESSIONS) {
    $MaxConcurrent = [int]$env:JULES_MAX_CONCURRENT_SESSIONS
}
if ($env:JULES_RATE_LIMIT_DELAY_MS) {
    $RateLimitDelayMs = [int]$env:JULES_RATE_LIMIT_DELAY_MS
}

Write-Host "Parallel dispatch config: max=$MaxConcurrent concurrent, rate=$RateLimitDelayMs ms delay" -ForegroundColor Cyan

$jobs = @()
$results = @()
$running = 0

foreach ($issueNum in $IssueNumbers) {
    while ($running -ge $MaxConcurrent) {
        $completed = 0
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            if ($jobs[$i].State -eq 'Completed' -or $jobs[$i].State -eq 'Failed') {
                $completed++
            }
        }
        if ($completed -gt 0) {
            $running -= $completed
            $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host "[$($running+1)/$MaxConcurrent] Dispatching Jules for Issue #$issueNum..." -ForegroundColor Yellow
    $job = Start-Job -ScriptBlock {
        param($issueNum, $repo, $autoPr, $scriptDir)
        & "$scriptDir\create-jules-session.ps1" -IssueNumber $issueNum -Repository $repo -AutoCreatePr:$autoPr
    } -ArgumentList $issueNum, $Repository, $AutoCreatePr.IsPresent, $ScriptDir
    $jobs += $job
    $running++

    Start-Sleep -Milliseconds $RateLimitDelayMs
}

Write-Host "`nWaiting for all dispatch jobs to complete..." -ForegroundColor Cyan
$jobs | Wait-Job | Out-Null

foreach ($job in $jobs) {
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    if ($result) {
        $results += $result
        Write-Host "  -> Session: $($result.SessionId), State: $($result.State)" -ForegroundColor Green
    }
}

Write-Host "`n=== Dispatch Summary ===" -ForegroundColor Cyan
$results | Select-Object IssueNumber, SessionId, SessionUrl, State | Format-Table -AutoSize

$activeCount = ($results | Where-Object { $_.State -eq 'ACTIVE' }).Count
Write-Host "Total dispatched: $($results.Count), Active: $activeCount" -ForegroundColor $(if ($activeCount -gt 0) { "Green" } else { "Yellow" })
