[CmdletBinding()]
param(
    [string]$SessionId,
    [int]$IssueNumber,
    [string]$Repository,
    [string]$ApiKey,
    [switch]$ApprovePlan,
    [string]$Message,
    [string]$MessageFile,
    [int]$ActivityPageSize = 20,
    [bool]$UpdateIssueBody = $true,
    [bool]$PostIssueComment = $true
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

if ([string]::IsNullOrWhiteSpace($SessionId) -and $IssueNumber -le 0) {
    throw "Bitte -SessionId oder -IssueNumber angeben."
}

if (-not [string]::IsNullOrWhiteSpace($MessageFile)) {
    if (-not (Test-Path $MessageFile)) {
        throw "Message-Datei nicht gefunden: $MessageFile"
    }

    $Message = Get-Content -Path $MessageFile -Raw
}

$resolvedRepository = $null
if ($IssueNumber -gt 0 -or $UpdateIssueBody -or $PostIssueComment) {
    $resolvedRepository = Resolve-GitHubRepository -Repository $Repository
}

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $reference = Get-JulesSessionReferenceFromIssue -Repository $resolvedRepository -IssueNumber $IssueNumber
    if ($reference) {
        $SessionId = $reference.SessionName
    } else {
        $fallback = Get-AllJulesSessions -ApiKey $ApiKey -PageSize 100 -MaxPages 5 |
            Where-Object { (Get-IssueNumberFromSession -Session $_) -eq $IssueNumber } |
            Sort-Object updateTime -Descending |
            Select-Object -First 1

        if (-not $fallback) {
            throw "Es wurde keine Jules Session fuer Issue #$IssueNumber gefunden."
        }

        $SessionId = [string]$fallback.name
    }
}

$session = Get-JulesSession -SessionIdOrName $SessionId -ApiKey $ApiKey
$sessionName = [string]$session.name
$sessionId = Resolve-JulesSessionId -SessionIdOrName $sessionName
$issueId = if ($IssueNumber -gt 0) { $IssueNumber } else { Get-IssueNumberFromSession -Session $session }
$beforeActivities = @(Get-AllJulesActivities -SessionIdOrName $sessionName -PageSize $ActivityPageSize -MaxPages 1 -ApiKey $ApiKey)
$latestBefore = Get-JulesLatestActivity -Activities $beforeActivities

$didApprovePlan = $false
$didSendMessage = $false

if ($ApprovePlan.IsPresent) {
    if ([string]$session.state -ne "AWAITING_PLAN_APPROVAL") {
        Write-JulesWarn "Session ist nicht in AWAITING_PLAN_APPROVAL, Freigabe wird trotzdem versucht."
    }

    Approve-JulesPlan -SessionIdOrName $sessionName -ApiKey $ApiKey
    $didApprovePlan = $true
    Write-JulesInfo "Plan freigegeben."
}

if (-not [string]::IsNullOrWhiteSpace($Message)) {
    if (@("COMPLETED", "FAILED") -contains [string]$session.state) {
        Write-JulesWarn "Die Session ist bereits $($session.state). Nachricht wurde nicht gesendet."
    } else {
        Send-JulesMessage -SessionIdOrName $sessionName -Message $Message -ApiKey $ApiKey
        $didSendMessage = $true
        Write-JulesInfo "Nachricht an Jules gesendet."
    }
}

$updatedSession = Get-JulesSession -SessionIdOrName $sessionName -ApiKey $ApiKey
$afterActivities = @(Get-AllJulesActivities -SessionIdOrName $sessionName -PageSize $ActivityPageSize -MaxPages 1 -ApiKey $ApiKey)
$latestAfter = Get-JulesLatestActivity -Activities $afterActivities

if ($issueId -and $resolvedRepository) {
    if ($UpdateIssueBody) {
        Sync-JulesIssueTracking -Repository $resolvedRepository -IssueNumber $issueId -Session $updatedSession -LatestActivity $latestAfter -StartingBranch ([string]$updatedSession.sourceContext.githubRepoContext.startingBranch) -SourceName ([string]$updatedSession.sourceContext.source)
    }

    if ($PostIssueComment -and ($didApprovePlan -or $didSendMessage)) {
        $commentLines = @(
            "## Jules Session Update",
            "",
            ('- Session ID: `{0}`' -f $sessionId),
            ('- Neuer Status: `{0}`' -f [string]$updatedSession.state)
        )

        if ($didApprovePlan) {
            $commentLines += "- Aktion: Plan freigegeben"
        }

        if ($didSendMessage) {
            $commentLines += "- Aktion: Nachricht an Jules gesendet"
        }

        $latestSummary = Get-JulesActivitySummary -Activity $latestAfter
        if (-not [string]::IsNullOrWhiteSpace($latestSummary)) {
            $commentLines += "- Letzte Aktivitaet: $latestSummary"
        }

        Add-GitHubIssueComment -Repository $resolvedRepository -IssueNumber $issueId -Body ($commentLines -join "`n")
    }
}

$recommendedAction = switch ([string]$updatedSession.state) {
    "AWAITING_PLAN_APPROVAL" { "Plan mit -ApprovePlan freigeben." ; break }
    "AWAITING_USER_FEEDBACK" { "Rueckmeldung mit -Message oder -MessageFile senden." ; break }
    "FAILED" { "Fehlerursache pruefen; ggf. neue Session starten oder manuell nacharbeiten." ; break }
    "PAUSED" { "Status pruefen und bei Bedarf Rueckmeldung an Jules senden." ; break }
    default { $null }
}

[pscustomobject]@{
    IssueNumber       = $issueId
    SessionId         = $sessionId
    SessionName       = $sessionName
    SessionUrl        = [string]$updatedSession.url
    StateBefore       = [string]$session.state
    StateAfter        = [string]$updatedSession.state
    ApprovedPlan      = $didApprovePlan
    SentMessage       = $didSendMessage
    PreviousActivity  = Get-JulesActivitySummary -Activity $latestBefore
    LatestActivity    = Get-JulesActivitySummary -Activity $latestAfter
    RecommendedAction = $recommendedAction
}
