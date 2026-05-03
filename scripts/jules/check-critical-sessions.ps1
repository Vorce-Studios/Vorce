Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")

$apiKey = Get-JulesApiKey

Write-Host "Fetching latest 100 critical sessions (AWAITING_USER_FEEDBACK, FAILED)..." -ForegroundColor Cyan
# Fetching exactly one page (100 sessions)
$sessions = @(Get-AllJulesSessions -ApiKey $apiKey -PageSize 100 -MaxPages 1)

$criticalSessions = New-Object System.Collections.Generic.List[object]

foreach ($session in $sessions) {
    $state = [string](Get-JulesObjectPropertyValue -Object $session -Name "state")

    # Filter by states requested by user
    if ($state -ne "AWAITING_USER_FEEDBACK" -and $state -ne "FAILED") {
        continue
    }

    $sourceContext = Get-JulesObjectPropertyValue -Object $session -Name "sourceContext"
    $githubRepoContext = Get-JulesObjectPropertyValue -Object $sourceContext -Name "githubRepoContext"
    $repo = [string](Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "repository")
    $source = [string](Get-JulesObjectPropertyValue -Object $sourceContext -Name "source")

    $isVorce = ($repo -like "*Vorce*" -or $source -like "*Vorce*" -or [string]::IsNullOrWhiteSpace($repo))
    $isExcluded = ($repo -like "*MrLongNight*" -or $source -like "*MrLongNight*")

    if ($isVorce -and -not $isExcluded) {
        $criticalSessions.Add($session)
    }
}

if ($criticalSessions.Count -eq 0) {
    Write-Host "No sessions found in AWAITING_USER_FEEDBACK or FAILED state within the last 100 sessions." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($criticalSessions.Count) critical sessions:" -ForegroundColor Yellow
Write-Host ""

foreach ($session in $criticalSessions) {
    $sourceContext = Get-JulesObjectPropertyValue -Object $session -Name "sourceContext"
    $githubRepoContext = Get-JulesObjectPropertyValue -Object $sourceContext -Name "githubRepoContext"

    $repo = [string](Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "repository")
    $issueNum = Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "issueNumber"
    $state = [string](Get-JulesObjectPropertyValue -Object $session -Name "state")
    $updatedAt = Get-JulesObjectPropertyValue -Object $session -Name "updateTime"
    $url = Get-JulesObjectPropertyValue -Object $session -Name "url"
    $name = [string](Get-JulesObjectPropertyValue -Object $session -Name "name")

    # Fetch latest activities (increased to 10 for better failure detection)
    $activities = @(Get-AllJulesActivities -SessionIdOrName $name -PageSize 10 -MaxPages 1 -ApiKey $apiKey)

    $bestActivity = $null
    if ($state -eq "FAILED") {
        # For FAILED sessions, explicitly look for the failure reason in the activity log
        $bestActivity = $activities | Where-Object { $null -ne (Get-JulesObjectPropertyValue -Object $_ -Name "sessionFailed") } | Select-Object -First 1
    }

    if ($null -eq $bestActivity) {
        # Fallback to absolute latest if no specific failure found or for other states
        $bestActivity = Get-JulesLatestActivity -Activities $activities
    }

    $summary = Get-JulesActivitySummary -Activity $bestActivity

    $color = if ($state -eq "FAILED") { "Red" } else { "Magenta" }

    $displayTitle = if (-not [string]::IsNullOrWhiteSpace($repo)) {
        "Issue #$issueNum - $repo"
    } else {
        "Session: $name (Unknown Repo)"
    }

    Write-Host $displayTitle -ForegroundColor $color
    Write-Host "  State:  $state"
    Write-Host "  Updated: $updatedAt"
    if ($summary) {
        Write-Host "  Latest:  $summary" -ForegroundColor Cyan
    }
    Write-Host "  URL:     $url"
    Write-Host ""
}
