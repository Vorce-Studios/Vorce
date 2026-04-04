[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$IssueNumber,

    [string]$Repository,

    [Parameter(Mandatory)]
    [string]$Status,

    [string]$Agent = "Gemini CLI",
    [string]$RemoteState,
    [string]$QueueState,
    [string]$WorkBranch,
    [string]$PullRequestUrl,
    [string]$LastUpdate,
    [string]$JulesSessionId,
    [string]$JulesSessionName,
    [switch]$ReopenIfClosed
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-github.ps1")

function Test-IsFinalStatus {
    param([AllowNull()][string]$Value)

    return @("Done", "Completed", "Closed", "Merged") -contains [string]$Value
}

function Get-IssueFormFieldValue {
    param(
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$FieldName
    )

    $pattern = "(?ms)^###\s+$([regex]::Escape($FieldName))\s*$\s*(?<value>.*?)(?=^###\s+|\z)"
    $match = [regex]::Match($Body, $pattern)
    if (-not $match.Success) {
        return $null
    }

    foreach ($line in ($match.Groups["value"].Value -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            return $trimmed
        }
    }

    return $null
}

function Set-IssueFormFields {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][hashtable]$Updates
    )

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    $body = if ($null -eq $issue.body) { "" } else { [string]$issue.body }

    foreach ($entry in $Updates.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            continue
        }

        $fieldName = [string]$entry.Key
        $fieldValue = [string]$entry.Value
        $pattern = "(?ms)(^###\s+$([regex]::Escape($fieldName))\s*$\s*)(?<value>.*?)(?=^###\s+|\z)"
        if ([regex]::IsMatch($body, $pattern)) {
            $replacement = '${1}' + $fieldValue + "`n`n"
            $body = [regex]::Replace($body, $pattern, $replacement, 1)
        }
    }

    Set-GitHubIssueBody -Repository $Repository -IssueNumber $IssueNumber -Body $body
}

function Resolve-ProjectStatusValue {
    param([AllowNull()][string]$Value)

    switch -Regex ([string]$Value) {
        '^(Done|Completed|Closed|Merged)$' { return "Done" }
        '^Blocked$' { return "PR CodeRework" }
        '^Todo$' { return "Todo" }
        default { return "In Progress" }
    }
}

function Resolve-ProjectTaskTypeValue {
    param([AllowNull()][string]$Value)

    switch -Regex ([string]$Value) {
        '^Verification$' { return "Test" }
        '^Implementation$' { return "Feature" }
        '^(Bug|Feature|Fix|Polish|Refactor|Test)$' { return [string]$Value }
        default { return "Feature" }
    }
}

function Resolve-ProjectPriorityValue {
    param([AllowNull()][string]$Value)

    switch -Regex (([string]$Value).Trim()) {
        '^(A|Critical|High)$' { return "A" }
        '^(B|Medium)$' { return "B" }
        '^(C|Low)$' { return "C" }
        default { return "B" }
    }
}

function Resolve-ProjectPermitValue {
    param([AllowNull()][string]$Value)

    switch -Regex (([string]$Value).Trim()) {
        '^(approved|rejected|clarification)$' { return [string]$Value }
        '^#\d+$' { return "approved" }
        '^\S+$' { return "approved" }
        default { return $null }
    }
}

function Resolve-ProjectAgentValue {
    param([AllowNull()][string]$Value)

    switch -Regex (([string]$Value).Trim()) {
        '^(Jules|AgentJules)$' { return "AgentJules" }
        '^(Gemini CLI|Codex / Gemini CLI)$' { return "Gemini CLI" }
        '^(Codex CLI|Codex)$' { return "Codex CLI" }
        '^Codex Web$' { return "Codex Web" }
        default { return $null }
    }
}

function Resolve-ProjectRemoteStateValue {
    param(
        [AllowNull()][string]$Value,
        [AllowNull()][string]$FallbackStatus
    )

    $normalized = (([string]$Value).Trim()).ToLowerInvariant()
    switch ($normalized) {
        "none" { return "none" }
        "jules_created" { return "jules_created" }
        "queued" { return "jules_created" }
        "planning" { return "jules_running" }
        "in_progress" { return "jules_running" }
        "jules_running" { return "jules_running" }
        "awaiting_plan_approval" { return "jules_waiting" }
        "awaiting_user_feedback" { return "jules_waiting" }
        "paused" { return "jules_waiting" }
        "jules_waiting" { return "jules_waiting" }
        "failed" { return "jules_failed" }
        "jules_failed" { return "jules_failed" }
        "jules_completed_no_pr" { return "jules_completed_no_pr" }
        "pr_draft" { return "pr_draft" }
        "pr_open" { return "pr_open" }
        "pr_checks_pending" { return "pr_checks_pending" }
        "pr_failed" { return "pr_failed" }
        "pr_closed" { return "pr_closed" }
        "merged" { return "merged" }
        "completed" { return "merged" }
        "closed" { return "merged" }
        "unknown" { return "unknown" }
    }

    if (Test-IsFinalStatus -Value $FallbackStatus) {
        return "merged"
    }

    return "unknown"
}

function Resolve-ProjectJulesSessionStatusValue {
    param(
        [AllowNull()][string]$RemoteState,
        [AllowNull()][string]$AgentValue,
        [AllowNull()][string]$SessionId
    )

    if ($AgentValue -eq "Gemini CLI") {
        return "n_a"
    }

    if ([string]::IsNullOrWhiteSpace($SessionId) -or $SessionId -eq "n/a") {
        return "not_started"
    }

    switch ((([string]$RemoteState).Trim()).ToLowerInvariant()) {
        "queued" { return "queued" }
        "planning" { return "planning" }
        "in-progress" { return "running" }
        "in_progress" { return "running" }
        "awaiting-plan-approval" { return "waiting" }
        "awaiting-user-feedback" { return "waiting" }
        "paused" { return "waiting" }
        "failed" { return "failed" }
        "completed" { return "completed" }
        "pr_open" { return "completed" }
        "pr-open" { return "completed" }
        "pr_checks_pending" { return "completed" }
        "pr-failed" { return "completed" }
        "pr_failed" { return "completed" }
        "pr_draft" { return "completed" }
        "pr-closed" { return "completed" }
        "pr_closed" { return "completed" }
        "merged" { return "completed" }
        default { return "unknown" }
    }
}

function Resolve-ProjectPrChecksStatusValue {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [AllowNull()][string]$PullRequestUrl,
        [AllowNull()][string]$AgentValue
    )

    if ([string]::IsNullOrWhiteSpace($PullRequestUrl)) {
        return "n_a"
    }

    $pullRequest = Get-GitHubPullRequest -Repository $Repository -PullRequestUrl $PullRequestUrl
    if ($null -eq $pullRequest) {
        return "unknown"
    }

    if ([string]$pullRequest.state -eq "MERGED") {
        return "merged"
    }

    if ([string]$pullRequest.state -eq "CLOSED") {
        return "closed"
    }

    if ($pullRequest.PSObject.Properties.Name -contains "isDraft" -and [bool]$pullRequest.isDraft) {
        return "draft"
    }

    $checks = @(Get-GitHubPullRequestChecks -Repository $Repository -PullRequestUrl $PullRequestUrl)
    if ($checks.Count -eq 0) {
        return "pending"
    }

    $failed = @(
        $checks |
            Where-Object {
                [string]$_.bucket -eq "fail" -or
                @("FAILURE", "FAILED", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED") -contains ([string]$_.state).ToUpperInvariant()
            }
    )
    if ($failed.Count -gt 0) {
        return "failed"
    }

    $pending = @(
        $checks |
            Where-Object {
                @("PENDING", "QUEUED", "IN_PROGRESS", "STARTUP_FAILURE", "WAITING") -contains ([string]$_.state).ToUpperInvariant()
            }
    )
    if ($pending.Count -gt 0) {
        return "pending"
    }

    return "passed"
}

function Resolve-ProjectSubAgentValue {
    param(
        [AllowNull()][string]$Value,
        [AllowNull()][string]$TaskTypeValue,
        [AllowNull()][string]$AgentValue
    )

    $normalized = ([string]$Value).Trim()
    if (-not [string]::IsNullOrWhiteSpace($normalized) -and $normalized -ne "none") {
        return $normalized
    }

    if ($AgentValue -eq "AgentJules") {
        return "coder"
    }

    if ($TaskTypeValue -eq "Test") {
        return "tester"
    }

    return "coder"
}

function Set-ProjectFieldByName {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][string]$FieldName,
        [AllowNull()][string]$Value
    )

    $field = Get-VorceProjectField -Context $Context -FieldName $FieldName
    if ($null -eq $field) {
        return
    }

    Set-VorceProjectFieldValue -Context $Context -ItemId $ItemId -Field $field -Value $Value
}

$resolvedRepository = Resolve-GitHubRepository -Repository $Repository
$issue = Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $IssueNumber

if ($ReopenIfClosed.IsPresent -and (Test-GitHubIssueClosed -Issue $issue)) {
    gh issue reopen $IssueNumber --repo $resolvedRepository | Out-Null
    $issue = Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $IssueNumber
}

$resolvedStatus = $Status.Trim()
$resolvedRemoteState = if ([string]::IsNullOrWhiteSpace($RemoteState)) {
    if (Test-IsFinalStatus -Value $resolvedStatus) { "completed" } elseif ($resolvedStatus -eq "Blocked") { "blocked" } else { "issue-only" }
} else {
    $RemoteState.Trim()
}

$resolvedQueueState = if ([string]::IsNullOrWhiteSpace($QueueState)) {
    if (Test-IsFinalStatus -Value $resolvedStatus) { "closed" } elseif ($resolvedStatus -eq "Blocked") { "user-review" } else { "issue-only" }
} else {
    $QueueState.Trim()
}

$resolvedWorkBranch = if ([string]::IsNullOrWhiteSpace($WorkBranch)) { "n/a" } else { $WorkBranch.Trim() }
$resolvedPullRequestUrl = if ([string]::IsNullOrWhiteSpace($PullRequestUrl)) { "" } else { $PullRequestUrl.Trim() }
$resolvedLastUpdate = if ([string]::IsNullOrWhiteSpace($LastUpdate)) { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $LastUpdate.Trim() }

Set-IssueFormFields -Repository $resolvedRepository -IssueNumber $IssueNumber -Updates @{
    "Status"       = $resolvedStatus
    "agent"        = $Agent
    "jules_session" = $(if ([string]::IsNullOrWhiteSpace($JulesSessionId)) { $null } else { $JulesSessionId.Trim() })
    "remote_state" = $resolvedRemoteState
    "work_branch"  = $resolvedWorkBranch
    "last_update"  = $resolvedLastUpdate
}

$updatedIssue = Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $IssueNumber
$updatedBody = if ($null -eq $updatedIssue.body) { "" } else { [string]$updatedIssue.body }

$sessionReference = if (-not [string]::IsNullOrWhiteSpace($JulesSessionId) -or -not [string]::IsNullOrWhiteSpace($JulesSessionName)) {
    @{
        SessionId   = if (-not [string]::IsNullOrWhiteSpace($JulesSessionId)) { $JulesSessionId.Trim() } else { "" }
        SessionName = if (-not [string]::IsNullOrWhiteSpace($JulesSessionName)) { $JulesSessionName.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($JulesSessionId)) { "sessions/$($JulesSessionId.Trim())" } else { "" }
    }
} else {
    Get-JulesSessionReferenceFromIssue -Repository $resolvedRepository -IssueNumber $IssueNumber
}
Upsert-JulesIssueTrackingBlock -Repository $resolvedRepository -IssueNumber $IssueNumber -Fields @{
    SessionId      = if ($sessionReference) { [string]$sessionReference.SessionId } else { "" }
    SessionName    = if ($sessionReference) { [string]$sessionReference.SessionName } else { "" }
    QueueState     = $resolvedQueueState
    RemoteState    = $resolvedRemoteState
    WorkBranch     = $resolvedWorkBranch
    PullRequestUrl = $resolvedPullRequestUrl
    LastUpdate     = $resolvedLastUpdate
}

$updatedIssue = Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $IssueNumber
$updatedBody = if ($null -eq $updatedIssue.body) { "" } else { [string]$updatedIssue.body }

$projectContext = Get-VorceProjectContext -Repository $resolvedRepository
if ($null -ne $projectContext) {
    $issueContentId = Get-GitHubIssueContentId -Repository $resolvedRepository -IssueNumber $IssueNumber
    if (-not [string]::IsNullOrWhiteSpace($issueContentId)) {
        $itemId = Ensure-VorceProjectItem -Context $projectContext -IssueContentId $issueContentId
        $projectTaskType = Resolve-ProjectTaskTypeValue -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "task_type")
        $projectAgent = Resolve-ProjectAgentValue -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "agent")
        $projectRemoteState = Resolve-ProjectRemoteStateValue -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "remote_state") -FallbackStatus (Get-IssueFormFieldValue -Body $updatedBody -FieldName "Status")
        $projectJulesSessionStatus = Resolve-ProjectJulesSessionStatusValue -RemoteState (Get-IssueFormFieldValue -Body $updatedBody -FieldName "remote_state") -AgentValue $projectAgent -SessionId (Get-IssueFormFieldValue -Body $updatedBody -FieldName "jules_session")
        $projectPrChecksStatus = Resolve-ProjectPrChecksStatusValue -Repository $resolvedRepository -PullRequestUrl $resolvedPullRequestUrl -AgentValue $projectAgent
        $projectSubAgent = Resolve-ProjectSubAgentValue -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "sub_agent") -TaskTypeValue $projectTaskType -AgentValue $projectAgent

        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "Status" -Value (Resolve-ProjectStatusValue -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "Status"))
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "task_id" -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "task_id")
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "area" -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "area")
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "task_type" -Value $projectTaskType
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "priority" -Value (Resolve-ProjectPriorityValue -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "priority"))
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "permit_issue" -Value (Resolve-ProjectPermitValue -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "permit_issue"))
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "agent" -Value $projectAgent
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "jules_session" -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "jules_session")
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "jules_session_status" -Value $projectJulesSessionStatus
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "pr_checks_status" -Value $projectPrChecksStatus
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "work_branch" -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "work_branch")
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "last_update" -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "last_update")
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "description" -Value (Get-IssueFormFieldValue -Body $updatedBody -FieldName "description")
        Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName "sub_agent" -Value $projectSubAgent
    }
}

Sync-VorceProjectFields -Repository $resolvedRepository -IssueNumber $IssueNumber -Fields @{
    JulesSessionStatus = Resolve-ProjectJulesSessionStatusValue -RemoteState $resolvedRemoteState -AgentValue $Agent -SessionId $JulesSessionId
    PrChecksStatus     = Resolve-ProjectPrChecksStatusValue -Repository $resolvedRepository -PullRequestUrl $resolvedPullRequestUrl -AgentValue $Agent
    QueueState     = $resolvedQueueState
    RemoteState    = $resolvedRemoteState
    WorkBranch     = $resolvedWorkBranch
    PullRequestUrl = $resolvedPullRequestUrl
    LastUpdate     = $resolvedLastUpdate
    NeedsAttention = if ($resolvedStatus -eq "Blocked") { "yes" } else { "no" }
}

$desiredLabels = if (Test-IsFinalStatus -Value $resolvedStatus) {
    @()
} elseif ($resolvedStatus -eq "Blocked") {
    @("status: blocked")
} else {
    @("status: in-progress")
}

Sync-GitHubIssueStatusLabels -Repository $resolvedRepository -IssueNumber $IssueNumber -Issue $issue -DesiredLabels $desiredLabels

[pscustomobject]@{
    IssueNumber    = $IssueNumber
    Repository     = $resolvedRepository
    Status         = $resolvedStatus
    Agent          = $Agent
    QueueState     = $resolvedQueueState
    RemoteState    = $resolvedRemoteState
    WorkBranch     = $resolvedWorkBranch
    PullRequestUrl = $resolvedPullRequestUrl
    LastUpdate     = $resolvedLastUpdate
}
