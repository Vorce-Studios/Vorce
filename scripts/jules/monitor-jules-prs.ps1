[CmdletBinding()]
param(
    [string]$Repository,
    [int]$IssueNumber,
    [string]$ApiKey,
    [int]$Limit = 100,
    [bool]$SyncIssueBody = $false,
    [switch]$AutoNudgeJules,
    [int]$ActivityPageSize = 10
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

function Get-ChecksSummary {
    param([object[]]$Checks)

    if (-not $Checks -or @($Checks).Length -eq 0) {
        return "no-required-checks"
    }
    $checks = @($Checks)

    $failed = @($checks | Where-Object { 
        $state = Get-JulesObjectPropertyValue -Object $_ -Name "state"
        $bucket = Get-JulesObjectPropertyValue -Object $_ -Name "bucket"
        @("FAILURE", "TIMED_OUT", "CANCELLED", "ERROR") -contains [string]$state -or @("fail", "error") -contains [string]$bucket 
    })
    if ($failed.Count -gt 0) {
        return "failing: " + (($failed | ForEach-Object { [string]$_.name } | Select-Object -Unique) -join ", ")
    }

    $pending = @($checks | Where-Object { 
        $state = Get-JulesObjectPropertyValue -Object $_ -Name "state"
        $bucket = Get-JulesObjectPropertyValue -Object $_ -Name "bucket"
        @("PENDING", "QUEUED", "IN_PROGRESS", "STARTUP_FAILURE") -contains [string]$state -or @("pending", "skipping") -contains [string]$bucket 
    })
    if ($pending.Count -gt 0) {
        return "pending: " + (($pending | ForEach-Object { [string]$_.name } | Select-Object -Unique) -join ", ")
    }

    return "green"
}

function Get-PrNudgeMessage {
    param(
        [AllowNull()][object]$PullRequest,
        [object[]]$Checks
    )

    if ($null -eq $PullRequest) {
        return $null
    }

    $messages = New-Object System.Collections.Generic.List[string]
    $mergeable = [string]$PullRequest.mergeable
    if ($mergeable -match "CONFLICT") {
        $messages.Add("Your PR has merge conflicts. Rebase or merge the latest target branch, resolve conflicts cleanly, and keep the required branch/PR naming unchanged.")
    }

    $failedChecks = @($Checks | Where-Object { @("FAILURE", "TIMED_OUT", "CANCELLED", "ERROR") -contains [string]$_.state -or @("fail", "error") -contains [string]$_.bucket })
    if ($failedChecks.Count -gt 0) {
        $failedNames = ($failedChecks | ForEach-Object { [string]$_.name } | Select-Object -Unique) -join ", "
        $messages.Add("Required PR checks are failing: $failedNames. Fix the failures, push the changes, and summarize the exact root cause.")
    }

    if ($messages.Count -eq 0) {
        return $null
    }

    $messages.Add("If a failure is external or flaky, report that explicitly instead of retrying blindly.")
    return $messages -join "`n"
}

$resolvedRepository = Resolve-GitHubRepository -Repository $Repository
$issues = if ($IssueNumber -gt 0) {
    @(
        Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $IssueNumber
    )
} else {
    @(Get-GitHubIssues -Repository $resolvedRepository -State "open" -Limit $Limit)
}

$rows = foreach ($issue in $issues) {
    $currentIssueNumber = [int]$issue.number
    $reference = Get-JulesSessionReferenceFromIssue -Repository $resolvedRepository -IssueNumber $currentIssueNumber
    if (-not $reference) {
        continue
    }

    $session = $null
    $latestActivity = $null
    try {
        $session = Get-JulesSession -SessionIdOrName $reference.SessionName -ApiKey $ApiKey
        if ($SyncIssueBody -or $AutoNudgeJules.IsPresent) {
            $activities = @(Get-AllJulesActivities -SessionIdOrName ([string]$session.name) -PageSize $ActivityPageSize -MaxPages 1 -ApiKey $ApiKey)
            $latestActivity = Get-JulesLatestActivity -Activities $activities
        }
    } catch {
        Write-JulesWarn "Session '$($reference.SessionName)' konnte nicht abgerufen werden: $($_.Exception.Message)"
    }

    if ($null -eq $session) {
        continue
    }

    $pullRequest = Find-GitHubPullRequestForIssue -Repository $resolvedRepository -IssueNumber $currentIssueNumber -SessionId (Resolve-JulesSessionId -SessionIdOrName ([string]$session.name))
    $checks = if ($null -eq $pullRequest) { @() } else { @(Get-GitHubPullRequestChecks -Repository $resolvedRepository -PullRequestUrl ([string]$pullRequest.url)) }
    $checksSummary = Get-ChecksSummary -Checks $checks

    if ($SyncIssueBody) {
        Sync-JulesIssueTracking -Repository $resolvedRepository -IssueNumber $currentIssueNumber -Session $session -LatestActivity $latestActivity -StartingBranch ([string]$session.sourceContext.githubRepoContext.startingBranch) -SourceName ([string]$session.sourceContext.source)
    }

    $appliedAction = $null
    if ($AutoNudgeJules.IsPresent) {
        $nudgeMessage = Get-PrNudgeMessage -PullRequest $pullRequest -Checks $checks
        if (-not [string]::IsNullOrWhiteSpace($nudgeMessage) -and @("COMPLETED", "FAILED") -notcontains [string]$session.state) {
            Send-JulesMessage -SessionIdOrName ([string]$session.name) -Message $nudgeMessage -ApiKey $ApiKey
            $appliedAction = "jules-nudged"
        }
    }

    $needsAttention =
        ($null -eq $pullRequest) -or
        ([string]$pullRequest.mergeable -match "CONFLICT") -or
        ($checksSummary -like "failing:*")

    [pscustomobject]@{
        IssueNumber       = $currentIssueNumber
        SessionId         = Resolve-JulesSessionId -SessionIdOrName ([string]$session.name)
        SessionState      = [string]$session.state
        PullRequestNumber = if ($null -eq $pullRequest) { $null } else { [int]$pullRequest.number }
        PullRequestTitle  = if ($null -eq $pullRequest) { $null } else { [string]$pullRequest.title }
        PullRequestUrl    = if ($null -eq $pullRequest) { $null } else { [string]$pullRequest.url }
        Mergeable         = if ($null -eq $pullRequest) { $null } else { [string]$pullRequest.mergeable }
        ReviewDecision    = if ($null -eq $pullRequest) { $null } else { [string]$pullRequest.reviewDecision }
        Checks            = $checksSummary
        LatestActivity    = if ($null -eq $latestActivity) { $null } else { Get-JulesActivitySummary -Activity $latestActivity }
        NeedsAttention    = $needsAttention
        AppliedAction     = $appliedAction
    }
}

$rows | Sort-Object -Property @{ Expression = { if ($_.NeedsAttention) { 0 } else { 1 } } }, IssueNumber
