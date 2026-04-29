Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")

$apiKey = Get-JulesApiKey

Write-Host "Fetching sessions..."
$sessions = @(Get-AllJulesSessions -ApiKey $apiKey -PageSize 100 -MaxPages 2)

$vorceSessions = $sessions | Where-Object {
    $repo = $_.sourceContext.githubRepoContext.repository
    ($repo -like '*Vorce*') -and ($repo -notlike '*MrLongNight*')
}

Write-Host "Found $($vorceSessions.Count) Vorce-Studios/Vorce sessions"
Write-Host ""

foreach ($session in $vorceSessions) {
    $repo = $session.sourceContext.githubRepoContext.repository
    $issueNum = $session.sourceContext.githubRepoContext.issueNumber
    $state = $session.state
    $updatedAt = $session.updateTime

    Write-Host "Issue #$issueNum - $repo"
    Write-Host "  State: $state"
    Write-Host "  Updated: $updatedAt"
    Write-Host ""
}