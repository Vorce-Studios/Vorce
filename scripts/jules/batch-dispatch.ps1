$issueNumbers = @(371, 370, 369, 368, 367)
$sessions = @()
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

foreach ($issue in $issueNumbers) {
    Write-Host "Dispatching Jules for Issue #$issue..."
    $result = & (Join-Path $ScriptDir "create-jules-session.ps1") -IssueNumber $issue -Repository "Vorce-Studios/Vorce" -AutoCreatePr
    $sessions += $result
    Write-Host "  -> Session: $($result.SessionId), State: $($result.State)"
    Start-Sleep -Milliseconds 800
}

Write-Host ""
Write-Host "Dispatched Sessions:"
$sessions | Select-Object IssueNumber, SessionId, SessionUrl, State | Format-Table -AutoSize
