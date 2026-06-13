# Vorce-Autopilot/src/lib/checkdoing-utils.ps1
# Hilfsfunktionen fuer den Check&Doing-Modus (ehemals Monitoring)

function Test-CheckDoingJulesCapacityState {
    param([AllowNull()][string]$State)
    $normalized = if ([string]::IsNullOrWhiteSpace($State)) { "QUEUED" } else { [string]$State }
    return $normalized -in @("QUEUED", "PLANNING", "IN_PROGRESS", "AWAITING_PLAN_APPROVAL")
}

function Add-DecisionPending {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Topic,
        [Parameter(Mandatory)][string]$Context,
        [string]$RemediationCommand = "",
        [string]$RemediationResult = "",
        [string]$AlertId = ""
    )

    if ([string]::IsNullOrWhiteSpace($AlertId)) {
        $AlertId = "alert-$(Get-Date -Format 'yyyyMMddHHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,4))"
    }

    $exists = $State.decisions_pending | Where-Object {
        $_.topic -eq $Topic -and ($null -eq $_.status -or $_.status -eq 'pending')
    }
    if (-not $exists) {
        $newAlert = [ordered]@{
            id         = $AlertId
            topic      = $Topic
            context    = $Context
            remediation_command = $RemediationCommand
            remediation_result  = $RemediationResult
            created_at = (Get-Date -Format 'o')
            status     = 'pending'
        }
        $hasClosed = $State.decisions_pending | Where-Object { $_.topic -eq $Topic -and ($_.status -eq 'closed' -or $_.status -eq 'ignored') }
        if (-not $hasClosed) {
            $State.decisions_pending += @($newAlert)
            Write-Host "[CHECK&DOING] Entscheidung hinzugefuegt: $Topic (ID: $AlertId)" -ForegroundColor Yellow
        } else {
            Write-Host "[CHECK&DOING] Alert fuer '$Topic' bereits geschlossen/ignoriert (uebersprungen)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[CHECK&DOING] Entscheidung existiert bereits (pending): $Topic" -ForegroundColor DarkGray
    }
}

function Get-NextCheckDoingRetryAt {
    param([Parameter(Mandatory)][object]$Config)
    $minutes = if (
        (Test-ObjectProperty -Object $Config -Name "wake_intervals") -and
        (Test-ObjectProperty -Object $Config.wake_intervals -Name "planning_minutes")
    ) { [int]$Config.wake_intervals.planning_minutes } else { 60 }
    return (Get-Date).AddMinutes($minutes).ToString('o')
}

function Sync-OpenPullRequestsToReviewQueue {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object[]]$PullRequests
    )

    foreach ($pr in $PullRequests) {
        $prNumber = [int]$pr.number
        $prUrl = if (Test-ObjectProperty -Object $pr -Name "url") { [string]$pr.url } else { "" }
        $prUpdatedAt = if (Test-ObjectProperty -Object $pr -Name "updatedAt") { [string]$pr.updatedAt } else { "" }
        $issueNumber = 0
        $matchingDelegation = $State.active_delegations | Where-Object { [string]$_.pr_url -eq $prUrl } | Select-Object -First 1
        if ($matchingDelegation) { $issueNumber = [int]$matchingDelegation.issue_number }

        Add-ReviewItem -State $State -IssueNumber $issueNumber -PrUrl $prUrl -PrNumber $prNumber -PrUpdatedAt $prUpdatedAt
    }
}

function Get-CheckDoingLabelNames {
    param([AllowNull()][object]$Issue)

    if ($null -eq $Issue -or -not (Test-ObjectProperty -Object $Issue -Name "labels") -or $null -eq $Issue.labels) {
        return @()
    }

    return @($Issue.labels | ForEach-Object {
        if ($_ -is [string]) { $_ } elseif (Test-ObjectProperty -Object $_ -Name "name") { [string]$_.name }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Add-CheckDoingWorkingQueueItem {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$IssueTitle,
        [Parameter(Mandatory)][string]$AgentProvider
    )

    Confirm-WorkingSessionsState -State $State
    $alreadyQueued = @($State.working_queue | Where-Object { [int]$_.issue_number -eq $IssueNumber }).Count -gt 0
    $alreadyRunning = @($State.working_sessions | Where-Object {
        [int]$_.issue_number -eq $IssueNumber -and [string]$_.status -in @("QUEUED", "IN_PROGRESS")
    }).Count -gt 0

    if ($alreadyQueued -or $alreadyRunning) {
        Write-Host "[CHECK&DOING] Working Session fuer Issue #$IssueNumber ist bereits geplant." -ForegroundColor DarkGray
        return
    }

    $State.working_queue += @([ordered]@{
        id             = "work-$IssueNumber-$(Get-Date -Format 'yyyyMMddHHmmss')"
        issue_number   = $IssueNumber
        issue_title    = $IssueTitle
        agent_provider = $AgentProvider
        status         = "QUEUED"
        queued_at      = (Get-Date -Format 'o')
    })
    Write-Host "[CHECK&DOING] Working Session geplant: Issue #$IssueNumber -> $AgentProvider" -ForegroundColor Cyan
}

function Get-CheckDoingJulesSafetyReason {
    param(
        [AllowNull()][string]$Title,
        [AllowNull()][string]$Body
    )

    $titleText = if ($null -eq $Title) { "" } else { [string]$Title }
    $bodyText = if ($null -eq $Body) { "" } else { [string]$Body }

    if ($titleText -match "_MAIs_") { return "Master-Issue ist kein Jules-Codeauftrag" }
    if ($titleText -match "(?i)Resolve-Merge-Conflicts?|Merge-Konflikt|Merge-Conflict|Konflikt") { return "Merge-Konflikte muessen lokal mit CLI geloest werden" }
    if ($titleText -match "(?i)Release-Readiness|Merge-Reihenfolge|Blocker-Matrix|PRs?[-_\s]*\d|PR-\d") { return "PR-/Release-Koordination ist lokale CLI-Arbeit, kein Jules-Codeauftrag" }
    if ($bodyText -match "(?i)\bMaster-Issue\b|Tracking-PR|Tracker|buendelt|bündelt|Bündelung|Nachverfolgung|Scope-Freeze") { return "Tracker-/Koordinationsauftrag ist kein Jules-Codeauftrag" }
    if ($bodyText.Length -lt 250) { return "Issue-Beschreibung ist zu kurz fuer sichere Jules-Delegation" }

    $hasScope = $bodyText -match "(?i)\b(Ziel|Goal|Scope|Beschreibung|Current problem|Acceptance|Acceptance-Evidence|Acceptance criteria|Definition of Done|Akzeptanz)\b"
    $hasConcreteWork = $bodyText -match "(?i)(crates/|scripts/|docs/|resources/|\.rs\b|\.ps1\b|\.ts\b|\.tsx\b|test|fixture|script|command|implement|fix|refactor|module|UI|CI)"
    if (-not $hasScope) { return "Issue hat keinen klaren Scope oder keine Acceptance-Kriterien" }
    if (-not $hasConcreteWork) { return "Issue nennt keine konkrete Code-/Test-/Dateiarbeit" }

    return ""
}

function Test-CheckDoingJulesIssueSafe {
    param(
        [AllowNull()][string]$Title,
        [AllowNull()][string]$Body
    )
    return [string]::IsNullOrWhiteSpace((Get-CheckDoingJulesSafetyReason -Title $Title -Body $Body))
}

function Test-CheckDoingLocalCliIssue {
    param(
        [AllowNull()][string]$Title,
        [AllowNull()][string]$Body
    )

    $titleText = if ($null -eq $Title) { "" } else { [string]$Title }
    $bodyText = if ($null -eq $Body) { "" } else { [string]$Body }
    $localTitle = $titleText -match "(?i)Merge-Konflikt|Merge-Conflict|Resolve-Merge-Conflicts?|Konflikt|PRs?[-_\s]*#?\d|PR-\d|CI|Recheck|pre-commit|Merge-Reihenfolge|Blocker-Matrix|Release-Readiness"

    if ($localTitle) { return $true }
    if ($titleText -match "(?i)^_*MAI|_MAIs_|Master") { return $false }

    return ($bodyText -match "(?i)status check|Check(s)? fehlgeschlagen|pre-commit|gh pr view|git merge|git diff --name-only --diff-filter=U")
}

function Test-CheckDoingIssueHasJulesSession {
    param([AllowNull()][object]$Issue)

    if ($null -eq $Issue) { return $false }
    $body = if ((Test-ObjectProperty -Object $Issue -Name "body") -and $null -ne $Issue.body) { [string]$Issue.body } else { "" }
    return (
        $body -match "<!--\s*jules-session-id:" -or
        $body -match "<!--\s*jules-session-name:" -or
        $body -match "<!--\s*vorce-queue-state:\s*dispatched"
    )
}

function Get-CheckDoingSessionId {
    param([AllowNull()][object]$Session)

    if ($null -eq $Session) { return "" }
    foreach ($field in @("name", "sessionName")) {
        if ((Test-ObjectProperty -Object $Session -Name $field) -and -not [string]::IsNullOrWhiteSpace([string]$Session.$field)) {
            if ([string]$Session.$field -match "sessions/(?<id>[^/\s]+)") { return $Matches["id"] }
            return [string]$Session.$field
        }
    }
    return ""
}

function Convert-AlertToMemory {
    param(
        [Parameter(Mandatory)][object]$DecisionPending,
        [string]$UserComment = ""
    )

    try {
        $memoryText = "IGNORE_ALERT: $($DecisionPending.topic)`nDetails: $($DecisionPending.context)"
        if (-not [string]::IsNullOrWhiteSpace($UserComment)) {
            $memoryText += "`nUser-Kommentar: $UserComment"
        }

        $result = Add-Memory `
            -Text $memoryText `
            -Type "temporary" `
            -Priority "medium" `
            -Source "audit_alert_close"

        if ($result) {
            Write-Host "[CHECK&DOING] Memory erstellt fuer geschlossenen Alert: $($DecisionPending.topic)" -ForegroundColor Cyan
            return $true
        }
        return $false
    } catch {
        Write-Warning "[CHECK&DOING] Konnte Memory fuer Alert nicht erstellen: $_"
        return $false
    }
}
