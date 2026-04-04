[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias("TaskDetails")]
    [string]$Prompt,
    [int]$IssueNumber,
    [string]$Repository,
    [string]$Title,
    [string]$SourceName,
    [string]$StartingBranch = "main",
    [string]$ApiKey,
    [switch]$AutoCreatePr,
    [switch]$RequirePlanApproval,
    [switch]$ForceNewSession,
    [bool]$UpdateIssueBody = $true,
    [bool]$PostIssueComment = $true,
    [bool]$ValidateSource = $true,
    [bool]$RemoveTodoUserLabel = $true
)

Set-StrictMode -Version 1.0
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

$resolvedRepository = $null
$issue = $null
$expectedPrTitle = $null
$expectedWorkBranch = $null
$reusedExistingSession = $false
$duplicateGuardReason = 'not_checked'
$duplicateActiveSessionIds = @()

if ($IssueNumber -gt 0) {
    $resolvedRepository = Resolve-GitHubRepository -Repository $Repository
    $issue = Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $IssueNumber
    $expectedPrTitle = Get-JulesPreferredPrTitle -IssueTitle ([string]$issue.title)
    $expectedWorkBranch = Get-JulesPreferredWorkBranch -IssueTitle ([string]$issue.title)
    $Prompt = Convert-IssueToJulesPrompt -Issue $issue -Repository $resolvedRepository -AdditionalPrompt $Prompt -AutoCreatePr:$AutoCreatePr.IsPresent
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = "Issue #$($issue.number): $($issue.title)"
    }
} elseif ([string]::IsNullOrWhiteSpace($Prompt)) {
    throw "Bitte entweder -IssueNumber oder -Prompt angeben."
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = ($Prompt -split "`r?`n" | Select-Object -First 1)
}

$Title = $Title.Trim()
if ($Title.Length -gt 100) {
    $Title = $Title.Substring(0, 100)
}

if ([string]::IsNullOrWhiteSpace($resolvedRepository) -and (-not [string]::IsNullOrWhiteSpace($Repository))) {
    $resolvedRepository = Resolve-GitHubRepository -Repository $Repository
}

$resolvedSourceName = Get-JulesSourceNameForRepository -Repository $resolvedRepository -SourceName $SourceName
if ($ValidateSource) {
    Confirm-JulesSourceExists -SourceName $resolvedSourceName -ApiKey $ApiKey | Out-Null
}

$createdSession = $null
$session = $null
$sessionId = $null
$resolvedAutomationMode = $null

if ($IssueNumber -gt 0 -and $resolvedRepository -and -not $ForceNewSession.IsPresent) {
    $guard = Get-JulesDuplicateDispatchGuard -IssueNumber $IssueNumber -Repository $resolvedRepository -ApiKey $ApiKey
    $duplicateGuardReason = [string]$guard.Reason
    $duplicateActiveSessionIds = @(
        @($guard.ActiveSessions) |
            ForEach-Object { Resolve-JulesSessionId -SessionIdOrName ([string]$_.name) }
    )

    if ([string]$guard.Status -eq 'blocked') {
        $activeSummary = @(
            @($guard.ActiveSessions) |
                ForEach-Object {
                    '{0} ({1})' -f (Resolve-JulesSessionId -SessionIdOrName ([string]$_.name)), [string]$_.state
                }
        ) -join ', '

        $trackedSummary = if ($null -ne $guard.TrackedReference -and -not [string]::IsNullOrWhiteSpace([string]$guard.TrackedReference.SessionId)) {
            [string]$guard.TrackedReference.SessionId
        } else {
            'n/a'
        }

        throw ("Duplicate-Dispatch-Guard blockiert neue Jules Session fuer Issue #{0}. Grund: {1}. Tracked Session: {2}. Aktive Sessions: {3}" -f $IssueNumber, [string]$guard.Reason, $trackedSummary, $(if ([string]::IsNullOrWhiteSpace($activeSummary)) { 'none' } else { $activeSummary }))
    }

    if ([string]$guard.Status -eq 'reuse' -and $null -ne $guard.PreferredSession) {
        $session = $guard.PreferredSession
        $sessionId = Resolve-JulesSessionId -SessionIdOrName ([string]$session.name)
        $createdSession = $session
        $reusedExistingSession = $true
        Write-JulesWarn ("Duplicate-Dispatch-Guard verwendet bestehende Jules Session {0} fuer Issue #{1}; es wird keine neue Session erstellt." -f $sessionId, $IssueNumber)
    }
}

if ($null -eq $session) {
    $payload = @{
        prompt = $Prompt
        title = $Title
        sourceContext = @{
            source = $resolvedSourceName
            githubRepoContext = @{
                startingBranch = $StartingBranch
            }
        }
    }

    if ($AutoCreatePr.IsPresent) {
        $payload["automationMode"] = "AUTO_CREATE_PR"
    }

    if ($RequirePlanApproval.IsPresent) {
        $payload["requirePlanApproval"] = $true
    }

    Write-JulesInfo "Erstelle Jules Session fuer '$Title'..."
    $createdSession = Invoke-JulesApiRequest -Method POST -Path "sessions" -Body $payload -ApiKey $ApiKey
    $sessionId = Resolve-JulesSessionId -SessionIdOrName ([string]$createdSession.name)
    $session = Get-JulesSession -SessionIdOrName ([string]$createdSession.name) -ApiKey $ApiKey
    if ($null -ne $createdSession -and [string]::IsNullOrWhiteSpace([string]$session.url) -and -not [string]::IsNullOrWhiteSpace([string]$createdSession.url)) {
        $session | Add-Member -NotePropertyName "url" -NotePropertyValue ([string]$createdSession.url) -Force
    }
    Write-JulesInfo "Session erstellt: $sessionId"
}

if ($null -ne $session -and $session.PSObject.Properties.Name -contains "automationMode") {
    $resolvedAutomationMode = [string]$session.automationMode
} elseif ($null -ne $createdSession -and $createdSession.PSObject.Properties.Name -contains "automationMode") {
    $resolvedAutomationMode = [string]$createdSession.automationMode
} elseif ($AutoCreatePr.IsPresent) {
    $resolvedAutomationMode = "AUTO_CREATE_PR"
}

if ($IssueNumber -gt 0 -and $resolvedRepository) {
    if ($UpdateIssueBody) {
        Sync-JulesIssueTracking -Repository $resolvedRepository -IssueNumber $IssueNumber -Session $session -LatestActivity $null -StartingBranch $StartingBranch -SourceName $resolvedSourceName | Out-Null
    }

    if ($PostIssueComment -and -not $reusedExistingSession) {
        $commentLines = @(
            "## Jules Session erstellt",
            "",
            ('- Session ID: `{0}`' -f $sessionId),
            ('- Status: `{0}`' -f [string]$session.state),
            "- Session URL: $($session.url)"
        )

        if (-not [string]::IsNullOrWhiteSpace($expectedPrTitle)) {
            $commentLines += ('- Required PR Title: `{0}`' -f $expectedPrTitle)
        }

        if (-not [string]::IsNullOrWhiteSpace($expectedWorkBranch)) {
            $commentLines += ('- Required Work Branch: `{0}`' -f $expectedWorkBranch)
        }

        if ($AutoCreatePr.IsPresent) {
            $commentLines += '- Auto-Create-PR: `AUTO_CREATE_PR`'
        }

        if ($RequirePlanApproval.IsPresent) {
            $commentLines += '- Plan Approval: `required`'
        }

        Add-GitHubIssueComment -Repository $resolvedRepository -IssueNumber $IssueNumber -Body ($commentLines -join "`n")
    }

    if ($RemoveTodoUserLabel) {
        Remove-GitHubIssueLabel -Repository $resolvedRepository -IssueNumber $IssueNumber -LabelName "Todo-UserISU"
    }
}

[pscustomobject]@{
    IssueNumber         = if ($IssueNumber -gt 0) { $IssueNumber } else { $null }
    Repository          = $resolvedRepository
    SessionId           = $sessionId
    SessionName         = [string]$session.name
    SessionUrl          = [string]$session.url
    Title               = [string]$session.title
    State               = [string]$session.state
    AutomationMode      = $resolvedAutomationMode
    RequirePlanApproval = [bool]$RequirePlanApproval.IsPresent
    ReusedExistingSession = $reusedExistingSession
    DuplicateGuardReason = $duplicateGuardReason
    ActiveSessionIds    = @($duplicateActiveSessionIds)
    SourceName          = $resolvedSourceName
    StartingBranch      = $StartingBranch
    ExpectedPrTitle     = $expectedPrTitle
    ExpectedWorkBranch  = $expectedWorkBranch
}
