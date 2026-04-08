[CmdletBinding()]
param(
    [int[]]$IssueNumber,
    [string]$Repository,
    [string]$ApiKey,
    [ValidateSet("open", "all")][string]$IssueState = "open",
    [int]$IssueLimit = 200,
    [int]$SessionPageSize = 100,
    [int]$SessionMaxPages = 10,
    [int]$ActivityPageSize = 10,
    [int]$StaleAfterHours = 12,
    [switch]$FailOnAttention
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

function Test-IsTrackedIssue {
    param([Parameter(Mandatory)][object]$Issue)

    $labels = Get-GitHubIssueLabelNames -Issue $Issue
    if ($labels -contains "jules-task" -or $labels -contains "Todo-UserISU") {
        return $true
    }

    $title = if ($null -eq $Issue.title) { "" } else { [string]$Issue.title }
    if ($title -match '^(I_|MAI-\d+_|__SI-\d+_MAI-\d+_|MFuser_#|MFusr_#|MF_#|MFsub_#)') {
        return $true
    }

    $body = if ($null -eq $Issue.body) { "" } else { [string]$Issue.body }
    if ($body.Contains($script:JulesIssueBlockStart) -or $body.Contains("<!-- jules-session-id:")) {
        return $true
    }

    return $false
}

function Test-IsStaleSnapshot {
    param([Parameter(Mandatory)][object]$Snapshot, [int]$StaleAfterHours)

    if ($null -eq $Snapshot) {
        return $false
    }

    $nonStaleStates = @(
        "not-started",
        "awaiting-session",
        "issue-only",
        "closed",
        "merged"
    )

    if ($nonStaleStates -contains [string]$Snapshot.RemoteState) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace([string]$Snapshot.LastUpdate)) {
        return $true
    }

    try {
        $lastUpdate = [datetimeoffset]$Snapshot.LastUpdate
        return (([datetimeoffset]::UtcNow - $lastUpdate).TotalHours -ge $StaleAfterHours)
    } catch {
        return $false
    }
}

$resolvedRepository = Resolve-GitHubRepository -Repository $Repository

$issues = if ($IssueNumber) {
    @($IssueNumber | ForEach-Object { Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $_ })
} else {
    $state = if ($IssueState -eq "all") { "all" } else { "open" }
    @(Get-GitHubIssues -Repository $resolvedRepository -State $state -Limit $IssueLimit | Where-Object { Test-IsTrackedIssue -Issue $_ })
}

$sessionApiKey = $null
$sessionsByIssueNumber = @{}

try {
    $sessionApiKey = Get-JulesApiKey -ApiKey $ApiKey
} catch {
    Write-JulesWarn "Keine Jules-API verfuegbar. Es werden nur native Issue-Daten synchronisiert."
}

if (-not [string]::IsNullOrWhiteSpace($sessionApiKey)) {
    $allSessions = @(Get-AllJulesSessions -PageSize $SessionPageSize -MaxPages $SessionMaxPages -ApiKey $sessionApiKey)
    $sortedSessions = @(
        $allSessions |
            Sort-Object {
                try {
                    [datetimeoffset]([string]$_.updateTime)
                } catch {
                    try {
                        [datetimeoffset]([string]$_.createTime)
                    } catch {
                        [datetimeoffset]::MinValue
                    }
                }
            } -Descending
    )

    foreach ($session in $sortedSessions) {
        $linkedIssueNumber = Get-IssueNumberFromSession -Session $session
        if ($null -eq $linkedIssueNumber) {
            continue
        }

        if (-not $sessionsByIssueNumber.ContainsKey([int]$linkedIssueNumber)) {
            $sessionsByIssueNumber[[int]$linkedIssueNumber] = $session
        }
    }
}

$results = foreach ($issue in @($issues | Sort-Object number)) {
    $session = $null
    if ($sessionsByIssueNumber.ContainsKey([int]$issue.number)) {
        $session = $sessionsByIssueNumber[[int]$issue.number]
    }

    if ($null -eq $session -and -not [string]::IsNullOrWhiteSpace($sessionApiKey)) {
        $reference = Get-JulesSessionReferenceFromIssue -Repository $resolvedRepository -IssueNumber ([int]$issue.number)
        if ($reference) {
            try {
                $session = Get-JulesSession -SessionIdOrName ([string]$reference.SessionName) -ApiKey $sessionApiKey
            } catch {
                Write-JulesWarn "Session-Referenz fuer Issue #$($issue.number) konnte nicht geladen werden: $($_.Exception.Message)"
            }
        }
    }

    $latestActivity = $null
    if ($null -ne $session -and -not [string]::IsNullOrWhiteSpace($sessionApiKey)) {
        $activities = @(Get-AllJulesActivities -SessionIdOrName ([string]$session.name) -PageSize $ActivityPageSize -MaxPages 1 -ApiKey $sessionApiKey)
        $latestActivity = Get-JulesLatestActivity -Activities $activities
    }

    $snapshot = Sync-VorceIssueTracking `
        -Repository $resolvedRepository `
        -IssueNumber ([int]$issue.number) `
        -Session $session `
        -LatestActivity $latestActivity `
        -StartingBranch $(if ($null -ne $session) { [string]$session.sourceContext.githubRepoContext.startingBranch } else { $null }) `
        -SourceName $(if ($null -ne $session) { [string]$session.sourceContext.source } else { $null })

    $isStale = Test-IsStaleSnapshot -Snapshot $snapshot -StaleAfterHours $StaleAfterHours
    $attention = ([string]$snapshot.NeedsAttention -eq "yes") -or $isStale

    if ($attention -and -not (Test-GitHubIssueClosed -Issue $issue)) {
        Sync-GitHubIssueStatusLabels -Repository $resolvedRepository -IssueNumber ([int]$issue.number) -Issue $issue -DesiredLabels @("status: blocked")
    }

    [pscustomobject]@{
        IssueNumber    = [int]$issue.number
        Title          = [string]$issue.title
        QueueState     = [string]$snapshot.QueueState
        RemoteState    = [string]$snapshot.RemoteState
        WorkBranch     = [string]$snapshot.WorkBranch
        PullRequestUrl = [string]$snapshot.PullRequestUrl
        LastUpdate     = [string]$snapshot.LastUpdate
        Attention      = $attention
        Stale          = $isStale
    }
}

$results = @($results)

if ($FailOnAttention.IsPresent -and ($results | Where-Object { $_.Attention })) {
    $results
    exit 2
}

$results
