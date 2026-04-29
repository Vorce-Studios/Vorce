[CmdletBinding()]
param(
    [string]$ApiKey
)

$apiKey = if ($ApiKey) { $ApiKey } else { $env:JULES_API_KEY }

$headers = @{
    'x-goog-api-key' = $apiKey
    'Content-Type' = 'application/json'
}

$response = Invoke-RestMethod -Uri 'https://jules.googleapis.com/v1alpha/sessions?pageSize=50' -Headers $headers -Method Get

$sessions = $response.sessions | Where-Object {
    $repo = $_.sourceContext.githubRepoContext.repository
    $source = $_.sourceContext.source
    ($repo -like '*Vorce*' -or $source -like '*Vorce*') -and ($repo -notlike '*MrLongNight*')
}

Write-Host "Found $($sessions.Count) Vorce-Studios/Vorce sessions:"
Write-Host ""

foreach ($session in $sessions) {
    $repo = $session.sourceContext.githubRepoContext.repository
    $issueNum = $session.sourceContext.githubRepoContext.issueNumber
    $state = $session.state
    $updatedAt = $session.updateTime
    $url = $session.url

    Write-Host "Issue #$issueNum - $repo"
    Write-Host "  State: $state"
    Write-Host "  Updated: $updatedAt"
    Write-Host "  URL: $url"
    Write-Host ""
}