Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")

$apiKey = Get-JulesApiKey

Write-Host "Fetching sessions..."
$sessions = @(Get-AllJulesSessions -ApiKey $apiKey -PageSize 100 -MaxPages 5)

$vorceSessions = $sessions | Where-Object {
    $source = $_.sourceContext.source
    $source -like '*Vorce*' -or $source -like '*MapFlow*'
}

Write-Host "Found $($vorceSessions.Count) Vorce & MapFlow sessions"
Write-Host ""

foreach ($session in $vorceSessions) {
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

    Write-Host "Issue #$issueNum - $repo"
    Write-Host "  State: $state"
    Write-Host "  Updated: $updatedAt"
    Write-Host ""
}
