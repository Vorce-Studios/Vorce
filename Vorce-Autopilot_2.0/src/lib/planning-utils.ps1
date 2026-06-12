# Vorce-Autopilot/src/lib/planning-utils.ps1
# Hilfsfunktionen fuer den Planning-Modus

function Add-WorkingQueueItem {
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
        Write-Host "[PLANNING] Working Session fuer Issue #$IssueNumber ist bereits geplant." -ForegroundColor DarkGray
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
    Write-Host "[PLANNING] Working Session geplant: Issue #$IssueNumber -> $AgentProvider" -ForegroundColor Cyan
}

function Test-AutopilotJulesIssueSafe {
    param(
        [AllowNull()][string]$Title,
        [AllowNull()][string]$Body
    )

    $titleText = if ($null -eq $Title) { "" } else { [string]$Title }
    $bodyText = if ($null -eq $Body) { "" } else { [string]$Body }

    if (
        (Test-VorceMasterIssueTitle -Title $titleText) -or
        $titleText -match "(?i)Resolve-Merge-Conflicts?|Merge-Konflikt|Merge-Conflict|Konflikt" -or
        $titleText -match "(?i)Release-Readiness|Merge-Reihenfolge|Blocker-Matrix|PRs?[-_\s]*\d|PR-\d"
    ) {
        return $false
    }

    $isTrackerLike = $bodyText -match "(?i)\bMaster-Issue\b|Tracking-PR|Tracker|buendelt|bündelt|Bündelung|Nachverfolgung|Scope-Freeze"
    $isExplicitSubTask = (Test-VorceSubIssueTitle -Title $titleText) -or (Test-VorceDefaultIssueTitle -Title $titleText)
    if ($isTrackerLike -and -not $isExplicitSubTask) {
        return $false
    }

    if ($bodyText.Length -lt 250) {
        return $false
    }

    $hasScope = $bodyText -match "(?i)\b(Ziel|Goal|Scope|Beschreibung|Current problem|Acceptance|Acceptance-Evidence|Acceptance criteria|Definition of Done|Akzeptanz)\b"
    $hasCodeWork = $bodyText -match "(?i)(crates/|scripts/|docs/|resources/|\.rs\b|\.ps1\b|\.ts\b|\.tsx\b|test|fixture|script|command|implement|fix|refactor|module|UI|CI)"
    if (-not ($hasScope -and $hasCodeWork)) {
        return $false
    }

    return $true
}

function Test-PlanningJulesCapacityState {
    param([AllowNull()][string]$State)

    $normalized = if ([string]::IsNullOrWhiteSpace($State)) { "QUEUED" } else { [string]$State }
    return $normalized -in @("QUEUED", "PLANNING", "IN_PROGRESS", "AWAITING_PLAN_APPROVAL")
}
