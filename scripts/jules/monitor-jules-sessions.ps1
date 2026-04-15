[CmdletBinding()]
param(
    [string[]]$SessionId,
    [int[]]$IssueNumber,
    [string]$Repository,
    [string]$ApiKey,
    [int]$PageSize = 50,
    [int]$MaxPages = 5,
    [int]$ActivityPageSize = 10,
    [switch]$OnlyActive,
    [switch]$OnlyNeedsAttention,
    [switch]$IncludeActivities,
    [switch]$Watch,
    [int]$IntervalSeconds = 60,
    [bool]$SyncIssueBody = $false,
    [switch]$FailOnAttention
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

function Resolve-MonitoredSessionNames {
    param([string[]]$SessionId, [int[]]$IssueNumber, [string]$Repository, [string]$ApiKey, [int]$PageSize, [int]$MaxPages)

    $sessionNames = @()

    if ($SessionId) {
        $sessionNames += @($SessionId | ForEach-Object { Resolve-JulesSessionName -SessionIdOrName $_ })
    }

    if ($IssueNumber) {
        $resolvedRepository = Resolve-GitHubRepository -Repository $Repository
        $allSessions = $null

        foreach ($issueId in $IssueNumber) {
            $reference = Get-JulesSessionReferenceFromIssue -Repository $resolvedRepository -IssueNumber $issueId
            if ($reference) {
                $sessionNames += $reference.SessionName
                continue
            }

            if ($null -eq $allSessions) {
                $allSessions = Get-AllJulesSessions -PageSize $PageSize -MaxPages $MaxPages -ApiKey $ApiKey
            }

            $match = $allSessions |
                Where-Object { (Get-IssueNumberFromSession -Session $_) -eq $issueId } |
                Sort-Object updateTime -Descending |
                Select-Object -First 1

            if ($match) {
                $sessionNames += [string]$match.name
            } else {
                Write-JulesWarn "Fuer Issue #$issueId wurde keine Jules Session gefunden."
            }
        }
    }

    if ($sessionNames.Count -gt 0) {
        return $sessionNames | Select-Object -Unique
    }

    return @(Get-AllJulesSessions -PageSize $PageSize -MaxPages $MaxPages -ApiKey $ApiKey | ForEach-Object { [string]$_.name })
}

function Get-MonitorSnapshot {
    param([string[]]$SessionNames, [int]$ActivityPageSize, [switch]$OnlyActive, [switch]$OnlyNeedsAttention, [switch]$IncludeActivities, [bool]$SyncIssueBody, [string]$Repository, [string]$ApiKey)

    $resolvedRepository = $null
    if ($SyncIssueBody -or $IssueNumber) {
        $resolvedRepository = Resolve-GitHubRepository -Repository $Repository
    }

    $results = foreach ($sessionName in $SessionNames) {
        $session = Get-JulesSession -SessionIdOrName $sessionName -ApiKey $ApiKey
        $needsAttention = Test-JulesAttentionRequired -Session $session
        $isActive = @("QUEUED", "PLANNING", "AWAITING_PLAN_APPROVAL", "AWAITING_USER_FEEDBACK", "IN_PROGRESS", "PAUSED") -contains [string]$session.state

        if ($OnlyActive -and -not $isActive) { continue }
        if ($OnlyNeedsAttention -and -not $needsAttention) { continue }

        $activities = @()
        if ($IncludeActivities -or $needsAttention -or $SyncIssueBody) {
            $activities = @(Get-AllJulesActivities -SessionIdOrName $sessionName -PageSize $ActivityPageSize -MaxPages 1 -ApiKey $ApiKey)
        }

        $latestActivity = Get-JulesLatestActivity -Activities $activities
        $issueId = Get-IssueNumberFromSession -Session $session

        if ($SyncIssueBody -and $issueId -and $resolvedRepository) {
            Sync-JulesIssueTracking -Repository $resolvedRepository -IssueNumber $issueId -Session $session -LatestActivity $latestActivity -StartingBranch ([string]$session.sourceContext.githubRepoContext.startingBranch) -SourceName ([string]$session.sourceContext.source)
        }

        [pscustomobject]@{
            IssueNumber      = $issueId
            SessionId        = Resolve-JulesSessionId -SessionIdOrName ([string]$session.name)
            Title            = [string]$session.title
            State            = [string]$session.state
            NeedsAttention   = $needsAttention
            UpdatedAt        = [string]$session.updateTime
            SessionUrl       = [string]$session.url
            PullRequestUrl   = Get-JulesSessionPullRequestUrl -Session $session
            LastActivity     = Get-JulesActivitySummary -Activity $latestActivity
            LastActivityTime = if ($latestActivity) { [string]$latestActivity.createTime } else { $null }
        }
    }

    return @($results | Sort-Object UpdatedAt -Descending)
}

$sessionNames = Resolve-MonitoredSessionNames -SessionId $SessionId -IssueNumber $IssueNumber -Repository $Repository -ApiKey $ApiKey -PageSize $PageSize -MaxPages $MaxPages

if (-not $Watch.IsPresent) {
    $snapshot = Get-MonitorSnapshot -SessionNames $sessionNames -ActivityPageSize $ActivityPageSize -OnlyActive:$OnlyActive.IsPresent -OnlyNeedsAttention:$OnlyNeedsAttention.IsPresent -IncludeActivities:$IncludeActivities.IsPresent -SyncIssueBody:$SyncIssueBody -Repository $Repository -ApiKey $ApiKey
    if ($FailOnAttention.IsPresent -and ($snapshot | Where-Object { $_.NeedsAttention })) {
        $snapshot
        exit 2
    }

    $snapshot
    return
}

Write-JulesInfo "Starte Jules-Monitoring. Intervall: $IntervalSeconds Sekunden."
while ($true) {
    $snapshot = Get-MonitorSnapshot -SessionNames $sessionNames -ActivityPageSize $ActivityPageSize -OnlyActive:$OnlyActive.IsPresent -OnlyNeedsAttention:$OnlyNeedsAttention.IsPresent -IncludeActivities:$IncludeActivities.IsPresent -SyncIssueBody:$SyncIssueBody -Repository $Repository -ApiKey $ApiKey

    Write-Host ""
    Write-Host ("[{0}] Jules Session Snapshot" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -ForegroundColor Green
    if ($snapshot.Count -eq 0) {
        Write-Host "Keine passenden Sessions gefunden." -ForegroundColor Yellow
    } else {
        $snapshot | Format-Table IssueNumber, SessionId, State, NeedsAttention, UpdatedAt, PullRequestUrl, LastActivity -AutoSize
    }

    if ($FailOnAttention.IsPresent -and ($snapshot | Where-Object { $_.NeedsAttention })) {
        exit 2
    }

    Start-Sleep -Seconds $IntervalSeconds
}
