[CmdletBinding()]
param(
    [string]$ApiKey
)

$apiKey = if ($ApiKey) { $ApiKey } else { $env:JULES_API_KEY }

$headers = @{
    'x-goog-api-key' = $apiKey
    'Content-Type' = 'application/json'
}

$response = Invoke-RestMethod -Uri 'https://jules.googleapis.com/v1alpha/sessions?pageSize=100' -Headers $headers -Method Get

$sessions = $response.sessions | Where-Object {
    $source = $_.sourceContext.source
    $source -like '*Vorce*' -or $source -like '*MapFlow*'
}

Write-Host "Found $($sessions.Count) Vorce & MapFlow sessions:"
Write-Host ""

foreach ($session in $sessions) {
    $source = $session.sourceContext.source
    $repo = if ($source -match "sources/github/(?<name>.*)") { $Matches["name"] } else { $source }
    $issueNum = $null
    foreach ($candidate in @([string]$session.title, [string]$session.prompt)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -match "Issue\s+#(?<id>\d+)") {
            $issueNum = [int]$Matches["id"]
            break
        }
    }
    $state = $session.state
    $updatedAt = $session.updateTime
    $url = $session.url

    Write-Host "Issue #$issueNum - $repo"
    Write-Host "  State: $state"
    Write-Host "  Updated: $updatedAt"
    Write-Host "  URL: $url"
    Write-Host ""
}
