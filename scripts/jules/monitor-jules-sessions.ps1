[CmdletBinding()]
param(
    [switch]$OnlyActive,
    [switch]$IncludeActivities,
    [int]$IssueNumber,
    [switch]$SyncIssueBody,
    [string]$ApiKey
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")

$apiKey = Get-JulesApiKey -ApiKey $ApiKey

Write-Host "Monitoring Jules sessions..." -ForegroundColor Cyan

$sessions = @(Get-AllJulesSessions -ApiKey $apiKey -PageSize 100 -MaxPages 5)
$now = [DateTime]::UtcNow
$staleThresholdHours = 1

$alertCount = 0

foreach ($session in $sessions) {
    $state = [string](Get-JulesObjectPropertyValue -Object $session -Name "state")
    $name = [string](Get-JulesObjectPropertyValue -Object $session -Name "name")
    $updatedAtStr = [string](Get-JulesObjectPropertyValue -Object $session -Name "updateTime")

    $sourceContext = Get-JulesObjectPropertyValue -Object $session -Name "sourceContext"
    $githubRepoContext = Get-JulesObjectPropertyValue -Object $sourceContext -Name "githubRepoContext"
    $sessionIssueNum = Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "issueNumber"
    $repo = [string](Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "repository")

    if ($IssueNumber -and $sessionIssueNum -ne $IssueNumber) {
        continue
    }

    $isActive = (-not (@("COMPLETED", "CLOSED", "CANCELED") -contains $state))
    if ($OnlyActive -and -not $isActive) {
        continue
    }

    $updatedAt = [DateTime]$updatedAtStr
    $updatedAtUtc = $updatedAt.ToUniversalTime()
    $timeSinceUpdate = $now - $updatedAtUtc

    $isFailed = ($state -eq "FAILED")
    $isStale = ($isActive -and -not $isFailed -and ($timeSinceUpdate.TotalHours -ge $staleThresholdHours))

    if ($isFailed -or $isStale) {
        $alertCount++
        $status = if ($isFailed) { "ERROR (Failed)" } else { "STALE (>$staleThresholdHours hr without progress)" }
        $color = if ($isFailed) { "Red" } else { "Yellow" }

        Write-Host "Session: $name" -ForegroundColor $color
        Write-Host "  Repo:  $repo"
        Write-Host "  Issue: $sessionIssueNum"
        Write-Host "  State: $state"
        Write-Host "  Alert: $status"
        Write-Host "  Last Updated: $updatedAtStr ($([math]::Round($timeSinceUpdate.TotalMinutes)) mins ago)"

        if ($IncludeActivities) {
            $activities = @(Get-AllJulesActivities -SessionIdOrName $name -PageSize 5 -MaxPages 1 -ApiKey $apiKey)
            if ($activities) {
                Write-Host "  Recent Activities:"
                foreach ($activity in $activities) {
                    $summary = Get-JulesActivitySummary -Activity $activity
                    $actTimeStr = [string](Get-JulesObjectPropertyValue -Object $activity -Name "createTime")
                    Write-Host "    - $actTimeStr : $summary"
                }
            }
        }

        Write-Host ""
    }
}

if ($SyncIssueBody) {
    Write-Host "SyncIssueBody switch passed but not fully implemented for monitoring in this base script." -ForegroundColor DarkGray
}

Write-Host "Monitoring complete. Found $alertCount alerts." -ForegroundColor Cyan
