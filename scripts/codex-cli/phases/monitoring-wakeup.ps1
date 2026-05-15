# scripts/codex-cli/phases/monitoring-wakeup.ps1
# Monitoring Mode: Check running Jules sessions, PRs, merge conflicts

Set-StrictMode -Version Latest

$PromptLibPath = Join-Path (Split-Path -Parent $PSScriptRoot) "lib\autopilot-prompts.ps1"
if (Test-Path $PromptLibPath) {
    . $PromptLibPath
}

function Get-VorceJulesFeedbackPrompt {
    param(
        [int]$IssueNumber,
        [string]$IssueTitle,
        [string]$LatestActivitySummary,
        [string]$Repository
    )

    $issueLine = if ($IssueNumber -gt 0) { "Issue: #$IssueNumber $IssueTitle" } else { "Issue: unbekannt" }
    return @"
Vorce Autopilot Controller-Antwort.
Repository: $Repository
$issueLine

Jules wartet auf User-Feedback. Fahre bitte mit der kleinstmoeglichen sicheren naechsten Aktion fort.

Regeln:
- Keine breite All-at-once-Loesung.
- Wenn es um Merge-Konflikte geht, bearbeite genau einen PR/Branch und halte den Scope auf Konfliktloesung plus unmittelbare CI-Folgen begrenzt.
- Wenn dir Kontext fehlt, dokumentiere den konkreten Blocker statt zu raten.
- Wenn die letzte Frage mehrere Optionen nennt, waehle die risikoaermste Option, die den Issue-Scope erfuellt.

Letzte bekannte Aktivitaet:
$LatestActivitySummary
"@.Trim()
}

function Get-JulesSessionRepository {
    param([AllowNull()][object]$Session)

    $sourceContext = Get-JulesObjectPropertyValue -Object $Session -Name "sourceContext"
    $githubRepoContext = Get-JulesObjectPropertyValue -Object $sourceContext -Name "githubRepoContext"
    return [string](Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "repository")
}

function Get-JulesSessionIssueNumberSafe {
    param([AllowNull()][object]$Session)

    $sourceContext = Get-JulesObjectPropertyValue -Object $Session -Name "sourceContext"
    $githubRepoContext = Get-JulesObjectPropertyValue -Object $sourceContext -Name "githubRepoContext"
    $issueNumber = Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "issueNumber"
    if ($issueNumber) { return [int]$issueNumber }

    try { return Get-IssueNumberFromSession -Session $Session } catch { return 0 }
}

function Get-JulesFeedbackTracker {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$SessionId
    )

    if (-not ($State.PSObject.Properties.Name -contains "jules_feedback_responses") -or $null -eq $State.jules_feedback_responses) {
        $State | Add-Member -MemberType NoteProperty -Name "jules_feedback_responses" -Value @() -Force
    }

    $existing = @($State.jules_feedback_responses | Where-Object { [string]$_.session_id -eq $SessionId } | Select-Object -First 1)
    if ($existing.Count -gt 0) { return $existing[0] }

    $tracker = [ordered]@{
        session_id   = $SessionId
        attempts     = 0
        last_sent_at = $null
        last_state   = $null
    }
    $State.jules_feedback_responses += @($tracker)
    return $tracker
}

function Resolve-JulesAwaitingFeedback {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Repository,
        [switch]$DryRun
    )

    $sessionName = [string](Get-JulesObjectPropertyValue -Object $Session -Name "name")
    $sessionId = Resolve-JulesSessionId -SessionIdOrName $sessionName
    $issueNum = Get-JulesSessionIssueNumberSafe -Session $Session
    $issueTitle = [string](Get-JulesObjectPropertyValue -Object $Session -Name "title")
    $maxRetries = [int]$Config.jules.auto_retry_feedback_max
    $tracker = Get-JulesFeedbackTracker -State $State -SessionId $sessionId
    $attempts = [int]$tracker.attempts

    if ($attempts -ge $maxRetries) {
        $topic = "Jules Session $sessionId braucht Hilfe"
        Write-Host "[MONITOR]   Jules $sessionId wartet weiter auf User-Feedback; Retry-Limit erreicht." -ForegroundColor Red
        if (-not $DryRun.IsPresent -and @($State.decisions_pending | Where-Object { $_.topic -eq $topic }).Count -eq 0) {
            $State.decisions_pending += @([ordered]@{
                topic        = $topic
                issue_number = $issueNum
                issue_title  = $issueTitle
                context      = "Session $sessionId ist nach $maxRetries automatischen Antworten weiter AWAITING_USER_FEEDBACK."
                created_at   = (Get-Date -Format 'o')
            })
            Save-AutopilotState -State $State
        }
        return
    }

    $latestSummary = ""
    try {
        $activities = @(Get-AllJulesActivities -SessionIdOrName $sessionName -PageSize 5 -MaxPages 1 -ApiKey $env:JULES_API_KEY)
        $latest = Get-JulesLatestActivity -Activities $activities
        $latestSummary = Get-JulesActivitySummary -Activity $latest
    } catch {
        $latestSummary = "Aktivitaeten konnten nicht geladen werden: $($_.Exception.Message)"
    }

    $message = Get-VorceJulesFeedbackPrompt -IssueNumber $issueNum -IssueTitle $issueTitle -LatestActivitySummary $latestSummary -Repository $Repository
    Write-Host ("[MONITOR]   -> Klaere Jules Feedback: Session {0}, Versuch {1}/{2}" -f $sessionId, ($attempts + 1), $maxRetries) -ForegroundColor Yellow

    if (-not $DryRun.IsPresent) {
        Send-JulesMessage -SessionIdOrName $sessionName -Message $message -ApiKey $env:JULES_API_KEY
        $tracker.attempts = $attempts + 1
        $tracker.last_sent_at = (Get-Date -Format 'o')
        $tracker.last_state = "AWAITING_USER_FEEDBACK"
        Save-AutopilotState -State $State

        if (Get-Command Add-AutopilotJournalEvent -ErrorAction SilentlyContinue) {
            Add-AutopilotJournalEvent -SessionType "monitoring" -Message ("Sent scoped feedback response to Jules session {0} for issue #{1}." -f $sessionId, $issueNum)
        }
    }
}

function Test-JulesTerminalState {
    param([string]$State)
    return $State -match "COMPLETED|FAILED|CANCEL|DONE|MERGED"
}

function Get-JulesLiveSessionLoad {
    param([object[]]$Sessions)

    $count = 0
    foreach ($session in @($Sessions)) {
        $julesState = [string](Get-JulesObjectPropertyValue -Object $session -Name "state")
        if ($julesState -match "^IN_PROGRESS$|^QUEUED$|^PLANNING$|^AWAITING_PLAN_APPROVAL$") {
            $count++
        }
    }
    return $count
}

function Test-PrActionExists {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$ActionType
    )

    return @($State.active_pr_actions | Where-Object {
        [int]$_.pr_number -eq $PullRequestNumber -and
        [string]$_.action_type -eq $ActionType -and
        [string]$_.status -notmatch "COMPLETED|FAILED|CANCELLED"
    }).Count -gt 0
}

function Start-JulesPrAction {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$JulesScriptDir,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][object]$PullRequest,
        [Parameter(Mandatory)][string]$ActionType,
        [string[]]$FailingChecks = @(),
        [switch]$DryRun
    )

    $prNum = [int]$PullRequest.number
    $head = [string]$PullRequest.headRefName
    $base = if ($PullRequest.PSObject.Properties.Name -contains "baseRefName" -and -not [string]::IsNullOrWhiteSpace([string]$PullRequest.baseRefName)) { [string]$PullRequest.baseRefName } else { "main" }
    $title = [string]$PullRequest.title
    if ([string]::IsNullOrWhiteSpace($head)) { return $false }
    if (Test-PrActionExists -State $State -PullRequestNumber $prNum -ActionType $ActionType) { return $false }

    $prompt = if ($ActionType -eq "merge_conflict") {
        Get-VorceJulesPrConflictPrompt -Repository $Repository -PullRequestNumber $prNum -HeadRefName $head -BaseRefName $base -PullRequestTitle $title
    } else {
        Get-VorceJulesPrCheckFixPrompt -Repository $Repository -PullRequestNumber $prNum -HeadRefName $head -BaseRefName $base -PullRequestTitle $title -FailingChecks $FailingChecks
    }

    Write-Host ("[MONITOR]   -> Starte Jules PR-Action {0} fuer PR #{1} auf Branch {2}" -f $ActionType, $prNum, $head) -ForegroundColor Yellow
    if ($DryRun.IsPresent) { return $true }

    $sessionResult = & "$JulesScriptDir\create-jules-session.ps1" `
        -Repository $Repository `
        -Title ("PR #{0}: {1}" -f $prNum, $ActionType) `
        -StartingBranch $head `
        -Prompt $prompt `
        -AutoCreatePr:$false `
        -UpdateIssueBody:$false `
        -PostIssueComment:$false `
        -ApiKey $env:JULES_API_KEY

    $sessionObject = @($sessionResult | Where-Object {
        $null -ne $_ -and $_ -isnot [string] -and ($_.PSObject.Properties.Name -contains "SessionId")
    } | Select-Object -Last 1)
    $sessionId = if ($sessionObject.Count -gt 0) { [string]$sessionObject[0].SessionId } else { "unknown" }

    $State.active_pr_actions += @([ordered]@{
        pr_number = $prNum
        pr_title = $title
        action_type = $ActionType
        branch = $head
        base = $base
        jules_session_id = $sessionId
        status = "QUEUED"
        started_at = (Get-Date -Format 'o')
        last_checked_at = (Get-Date -Format 'o')
    })
    Save-AutopilotState -State $State

    if (Get-Command Add-AutopilotJournalEvent -ErrorAction SilentlyContinue) {
        Add-AutopilotJournalEvent -SessionType "monitoring" -Message ("Started Jules PR action {0} session {1} for PR #{2}." -f $ActionType, $sessionId, $prNum)
    }
    Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
    return $true
}

function Add-JulesCheckFixComment {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][object]$PullRequest,
        [string[]]$FailingChecks = @(),
        [switch]$DryRun
    )

    $prNum = [int]$PullRequest.number
    if (Test-PrActionExists -State $State -PullRequestNumber $prNum -ActionType "check_fix_comment") {
        return $false
    }

    $body = Get-VorceJulesPrCheckFixComment `
        -Repository $Repository `
        -PullRequestNumber $prNum `
        -HeadRefName ([string]$PullRequest.headRefName) `
        -BaseRefName ([string]$PullRequest.baseRefName) `
        -PullRequestTitle ([string]$PullRequest.title) `
        -FailingChecks $FailingChecks

    Write-Host ("[MONITOR]   -> Poste @Jules Check-Fix-Kommentar auf PR #{0}" -f $prNum) -ForegroundColor Yellow
    if (-not $DryRun.IsPresent) {
        $result = & gh pr comment $prNum --repo $Repository --body $body 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("[MONITOR]   @Jules Kommentar fuer PR #{0} fehlgeschlagen: {1}" -f $prNum, ($result | Out-String))
            return $false
        }

        $State.active_pr_actions += @([ordered]@{
            pr_number = $prNum
            pr_title = [string]$PullRequest.title
            action_type = "check_fix_comment"
            branch = [string]$PullRequest.headRefName
            base = [string]$PullRequest.baseRefName
            status = "COMMENTED"
            started_at = (Get-Date -Format 'o')
            last_checked_at = (Get-Date -Format 'o')
        })
        Save-AutopilotState -State $State
    }
    return $true
}

function Start-JulesConflictReplacementSession {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$JulesScriptDir,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][object]$PullRequest,
        [switch]$DryRun
    )

    $prNum = [int]$PullRequest.number
    $base = if (-not [string]::IsNullOrWhiteSpace([string]$PullRequest.baseRefName)) { [string]$PullRequest.baseRefName } else { "main" }
    Write-Host ("[MONITOR]   -> Zu viele Konflikte in PR #{0}; schliesse Alt-PR und starte frische Jules-Neuimplementierung." -f $prNum) -ForegroundColor Yellow
    if ($DryRun.IsPresent) { return $true }

    $sessionResult = & "$JulesScriptDir\create-jules-session.ps1" `
        -Repository $Repository `
        -Title ("Replacement for conflicted PR #{0}" -f $prNum) `
        -StartingBranch $base `
        -Prompt (Get-VorceJulesPrConflictReplacementPrompt -Repository $Repository -PullRequestNumber $prNum -BaseRefName $base -PullRequestTitle ([string]$PullRequest.title)) `
        -AutoCreatePr `
        -UpdateIssueBody:$false `
        -PostIssueComment:$false `
        -ApiKey $env:JULES_API_KEY

    $sessionObject = @($sessionResult | Where-Object {
        $null -ne $_ -and $_ -isnot [string] -and ($_.PSObject.Properties.Name -contains "SessionId")
    } | Select-Object -Last 1)
    $sessionId = if ($sessionObject.Count -gt 0) { [string]$sessionObject[0].SessionId } else { "unknown" }

    $closeResult = & gh pr close $prNum --repo $Repository --delete-branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning ("[MONITOR]   Alt-PR #{0} konnte nach Jules-Eskalation nicht sauber geschlossen werden: {1}" -f $prNum, ($closeResult | Out-String))
    }

    $State.active_pr_actions += @([ordered]@{
        pr_number = $prNum
        pr_title = [string]$PullRequest.title
        action_type = "merge_conflict_replacement"
        branch = [string]$PullRequest.headRefName
        base = $base
        jules_session_id = $sessionId
        status = "QUEUED"
        started_at = (Get-Date -Format 'o')
        last_checked_at = (Get-Date -Format 'o')
    })
    Save-AutopilotState -State $State
    Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
    return $true
}

function Invoke-CliPrConflictResolution {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$JulesScriptDir,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][object]$PullRequest,
        [switch]$DryRun
    )

    $prNum = [int]$PullRequest.number
    if (Test-PrActionExists -State $State -PullRequestNumber $prNum -ActionType "merge_conflict_cli") {
        return $false
    }

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ".."))
    $worktreeRoot = Join-Path $repoRoot "scripts\codex-cli\tmp\pr-worktrees"
    $worktreePath = Join-Path $worktreeRoot ("pr-{0}-{1}" -f $prNum, [guid]::NewGuid().ToString("N"))
    $prompt = Get-VorceCliPrConflictResolutionPrompt `
        -Repository $Repository `
        -PullRequestNumber $prNum `
        -HeadRefName ([string]$PullRequest.headRefName) `
        -BaseRefName ([string]$PullRequest.baseRefName) `
        -PullRequestTitle ([string]$PullRequest.title)

    Write-Host ("[MONITOR]   -> Loese Merge-Konflikt fuer PR #{0} primaer per CLI-Route." -f $prNum) -ForegroundColor Yellow

    if (-not $DryRun.IsPresent) {
        if (-not (Test-Path $worktreeRoot)) { New-Item -ItemType Directory -Path $worktreeRoot -Force | Out-Null }
        $head = [string]$PullRequest.headRefName
        $base = if (-not [string]::IsNullOrWhiteSpace([string]$PullRequest.baseRefName)) { [string]$PullRequest.baseRefName } else { "main" }

        & git -C $repoRoot fetch origin $head $base 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch fuer PR #$prNum fehlgeschlagen."
        }

        & git -C $repoRoot worktree add --detach $worktreePath ("origin/{0}" -f $head) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree add fuer PR #$prNum fehlgeschlagen."
        }

        & git -C $worktreePath checkout -B ("autopilot-pr-{0}-{1}" -f $prNum, [guid]::NewGuid().ToString("N").Substring(0, 8)) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Temp-Branch fuer PR #$prNum konnte nicht erstellt werden."
        }

        & git -C $worktreePath merge --no-edit ("origin/{0}" -f $base) 2>&1 | Out-Null
    }

    $result = Invoke-CliTask -QuotaRegistry $QuotaRegistry -TaskType "merge_conflict_resolution" -Prompt $prompt -WorkingDirectory $(if ($DryRun.IsPresent) { $repoRoot } else { $worktreePath }) -DryRun:$DryRun

    if ($DryRun.IsPresent) { return [bool]$result.success }

    $legacyTopic = "PR #$prNum hat Merge-Konflikte"
    $State.decisions_pending = @($State.decisions_pending | Where-Object { [string]$_.topic -ne $legacyTopic })

    $status = if (-not $result.success) {
        "FAILED"
    } elseif ([string]$result.output -match "Result:\s*TOO_MANY_CONFLICTS") {
        "ESCALATED_TO_JULES"
    } elseif ([string]$result.output -match "Result:\s*BLOCKED") {
        "BLOCKED"
    } else {
        "COMPLETED"
    }

    $State.active_pr_actions += @([ordered]@{
        pr_number = $prNum
        pr_title = [string]$PullRequest.title
        action_type = "merge_conflict_cli"
        branch = [string]$PullRequest.headRefName
        base = [string]$PullRequest.baseRefName
        provider = [string]$result.provider
        status = $status
        worktree = $worktreePath
        last_output_excerpt = if ([string]::IsNullOrWhiteSpace([string]$result.output)) { $null } else { ([string]$result.output).Substring(0, [Math]::Min(1000, ([string]$result.output).Length)) }
        started_at = (Get-Date -Format 'o')
        last_checked_at = (Get-Date -Format 'o')
    })
    Save-AutopilotState -State $State

    if ($status -eq "ESCALATED_TO_JULES") {
        return Start-JulesConflictReplacementSession -State $State -QuotaRegistry $QuotaRegistry -JulesScriptDir $JulesScriptDir -Repository $Repository -PullRequest $PullRequest
    }

    if ($status -eq "COMPLETED") {
        & git -C $worktreePath push origin ("HEAD:{0}" -f [string]$PullRequest.headRefName) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $status = "FAILED"
            $State.active_pr_actions[-1].status = $status
            Save-AutopilotState -State $State
        } else {
            & git -C $repoRoot worktree remove --force $worktreePath 2>&1 | Out-Null
        }
    }

    if ($status -eq "BLOCKED" -or $status -eq "FAILED") {
        $topic = "PR #$prNum Konfliktloesung blockiert"
        if (@($State.decisions_pending | Where-Object { $_.topic -eq $topic }).Count -eq 0) {
            $State.decisions_pending += @([ordered]@{
                topic = $topic
                context = "CLI-Route fuer Merge-Konflikt konnte PR #$prNum nicht sauber loesen."
                created_at = (Get-Date -Format 'o')
            })
            Save-AutopilotState -State $State
        }
    }

    return ($status -eq "COMPLETED")
}

function Start-JulesBacklogDelegation {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$JulesScriptDir,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][object]$BacklogItem,
        [switch]$DryRun
    )

    $issueNum = [int]$BacklogItem.issue_number
    if ($issueNum -le 0) { return $false }
    if (@($State.active_delegations | Where-Object { [int]$_.issue_number -eq $issueNum }).Count -gt 0) { return $false }

    Write-Host ("[MONITOR]   -> Starte Backlog-Jules-Session fuer Issue #{0}" -f $issueNum) -ForegroundColor Green
    if ($DryRun.IsPresent) { return $true }

    $sessionResult = & "$JulesScriptDir\create-jules-session.ps1" `
        -IssueNumber $issueNum `
        -Repository $Repository `
        -Prompt (Get-VorceJulesImplementationPrompt -IssueNumber $issueNum -Repository $Repository) `
        -AutoCreatePr `
        -ApiKey $env:JULES_API_KEY

    $sessionObject = @($sessionResult | Where-Object {
        $null -ne $_ -and $_ -isnot [string] -and ($_.PSObject.Properties.Name -contains "SessionId")
    } | Select-Object -Last 1)
    $sessionId = if ($sessionObject.Count -gt 0) { [string]$sessionObject[0].SessionId } else { "unknown" }
    Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle ([string]$BacklogItem.issue_title) -JulesSessionId $sessionId
    Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
    return $true
}

function Invoke-MonitoringWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[MONITOR] ========== Monitoring Wake-Up ==========" -ForegroundColor Blue

    $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $JulesScriptDir = Join-Path (Split-Path -Parent $ScriptDir) "jules"

    # Load Jules API functions
    $julesApiPath = Join-Path $JulesScriptDir "jules-api.ps1"
    if (Test-Path $julesApiPath) {
        . $julesApiPath
    } elseif ($State.active_delegations.Count -gt 0 -and -not $DryRun.IsPresent) {
        throw "Jules API Helper nicht gefunden: $julesApiPath"
    }

    $allLiveJulesSessions = @()
    if (Get-Command Get-AllJulesSessions -ErrorAction SilentlyContinue) {
        try {
            $sessionPollMaxPages = if ($Config.jules.PSObject.Properties.Name -contains "session_poll_max_pages") { [int]$Config.jules.session_poll_max_pages } else { 20 }
            $allLiveJulesSessions = @(Get-AllJulesSessions -ApiKey $env:JULES_API_KEY -PageSize 100 -MaxPages $sessionPollMaxPages)
        } catch {
            Write-Warning "[MONITOR] Jules Live-Session-Liste konnte nicht geladen werden: $($_.Exception.Message)"
        }
    }
    $liveSessionLoad = Get-JulesLiveSessionLoad -Sessions $allLiveJulesSessions

    # --- Step 1: Check active Jules sessions ---
    Write-Host "[MONITOR] Pruefe $($State.active_delegations.Count) aktive Delegierungen..." -ForegroundColor Cyan

    $toRemove = @()

    foreach ($delegation in @($State.active_delegations)) {
        $issueNum = [int]$delegation.issue_number
        $sessionId = [string]$delegation.jules_session_id

        if ($issueNum -le 0 -or [string]::IsNullOrWhiteSpace($sessionId) -or $sessionId -like "dry-run-*") {
            Write-Host ("[MONITOR]   #{0} veraltete/ungueltige Test-Delegierung entfernt." -f $issueNum) -ForegroundColor DarkGray
            if (-not $DryRun.IsPresent) {
                Complete-Delegation -State $State -IssueNumber $issueNum -Result "stale-dry-run"
            }
            continue
        }

        try {
            $session = Get-JulesSession -SessionIdOrName $sessionId -ApiKey $env:JULES_API_KEY
            $julesState = [string]$session.state

            Write-Host ("[MONITOR]   #{0} ({1}): {2}" -f $issueNum, $sessionId, $julesState) -ForegroundColor $(
                switch ($julesState) {
                    "COMPLETED"  { "Green" }
                    "IN_PROGRESS" { "Cyan" }
                    "QUEUED"     { "DarkGray" }
                    "PLANNING"   { "Cyan" }
                    default      { "Yellow" }
                }
            )

            if (-not $DryRun.IsPresent) {
                Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $julesState
            }

            switch ($julesState) {
                "COMPLETED" {
                    # Check for PR
                    $prUrl = Get-JulesSessionPullRequestUrl -Session $session
                    if (-not [string]::IsNullOrWhiteSpace($prUrl)) {
                        Write-Host "[MONITOR]   -> PR gefunden: $prUrl" -ForegroundColor Green
                        if (-not $DryRun.IsPresent) {
                            Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $julesState -PrUrl $prUrl
                            $prNumber = if ($prUrl -match '/pull/(\d+)') { [int]$Matches[1] } else { 0 }
                            Add-ReviewItem -State $State -IssueNumber $issueNum -PrUrl $prUrl -PrNumber $prNumber
                        }
                    }
                    if (-not $DryRun.IsPresent) {
                        Complete-Delegation -State $State -IssueNumber $issueNum -Result "completed"
                    }
                }
                "AWAITING_PLAN_APPROVAL" {
                    if ($Config.jules.auto_approve_plans) {
                        Write-Host "[MONITOR]   -> Auto-Approve Plan" -ForegroundColor Yellow
                        if (-not $DryRun.IsPresent) {
                            Approve-JulesPlan -SessionIdOrName $sessionId -ApiKey $env:JULES_API_KEY
                        }
                    }
                }
                "AWAITING_USER_FEEDBACK" {
                    $retryCount = [int]$delegation.retry_count
                    $maxRetries = [int]$Config.jules.auto_retry_feedback_max

                    if ($retryCount -lt $maxRetries) {
                        $retryMsg = "[MONITOR]   -> Auto-Retry ({0}/{1})" -f ($retryCount + 1), $maxRetries
                        Write-Host $retryMsg -ForegroundColor Yellow
                        Resolve-JulesAwaitingFeedback -State $State -Config $Config -Session $session -Repository $repo -DryRun:$DryRun
                        if (-not $DryRun.IsPresent) {
                            $delegation.retry_count = $retryCount + 1
                            Save-AutopilotState -State $State
                        }
                    } else {
                        Write-Host "[MONITOR]   -> ESKALATION: Braucht manuellen Eingriff!" -ForegroundColor Red
                        $topic = "Jules Session #$issueNum braucht Hilfe"
                        if (-not $DryRun.IsPresent -and @($State.decisions_pending | Where-Object { $_.topic -eq $topic }).Count -eq 0) {
                            $State.decisions_pending += @([ordered]@{
                                topic        = $topic
                                issue_number = $issueNum
                                issue_title  = [string]$delegation.issue_title
                                context      = "Session $sessionId ist nach $maxRetries Retries immer noch AWAITING_USER_FEEDBACK."
                                created_at   = (Get-Date -Format 'o')
                            })
                        }
                    }
                }
                "FAILED" {
                    Write-Host "[MONITOR]   -> FAILED! Logge Fehler." -ForegroundColor Red
                    if (-not $DryRun.IsPresent) {
                        Add-ErrorLog -State $State -Message "Jules session failed for #$issueNum" -Context "Session: $sessionId"
                        Complete-Delegation -State $State -IssueNumber $issueNum -Result "failed"
                    }
                }
            }
        } catch {
            Write-Warning ("[MONITOR]   #{0} API-Fehler: {1}" -f $issueNum, $_)
            Add-ErrorLog -State $State -Message "API error for #$issueNum" -Context $_.Exception.Message
        }
    }

    # --- Step 1a: Check active PR action sessions ---
    if ($State.active_pr_actions.Count -gt 0) {
        Write-Host "[MONITOR] Pruefe $($State.active_pr_actions.Count) aktive PR-Actions..." -ForegroundColor Cyan
    }
    foreach ($prAction in @($State.active_pr_actions)) {
        $sessionId = [string]$prAction.jules_session_id
        if ([string]::IsNullOrWhiteSpace($sessionId) -or $sessionId -eq "unknown") { continue }
        try {
            $session = Get-JulesSession -SessionIdOrName $sessionId -ApiKey $env:JULES_API_KEY
            $julesState = [string](Get-JulesObjectPropertyValue -Object $session -Name "state")
            Write-Host ("[MONITOR]   PR #{0} action {1}: {2}" -f ([int]$prAction.pr_number), ([string]$prAction.action_type), $julesState) -ForegroundColor Cyan
            if (-not $DryRun.IsPresent) {
                $prAction.status = $julesState
                $prAction.last_checked_at = (Get-Date -Format 'o')
                if ($julesState -eq "AWAITING_USER_FEEDBACK") {
                    Resolve-JulesAwaitingFeedback -State $State -Config $Config -Session $session -Repository $repo -DryRun:$DryRun
                }
                if (Test-JulesTerminalState -State $julesState) {
                    $prAction.completed_at = (Get-Date -Format 'o')
                }
                Save-AutopilotState -State $State
            }
        } catch {
            Write-Warning "[MONITOR] PR-Action Session $sessionId konnte nicht geprueft werden: $($_.Exception.Message)"
        }
    }

    # --- Step 1b: Check Jules sessions that are not present in active_delegations ---
    $monitorUntracked = $Config.jules.PSObject.Properties.Name -contains "monitor_untracked_sessions" -and [bool]$Config.jules.monitor_untracked_sessions
    if ($monitorUntracked -and (Get-Command Get-AllJulesSessions -ErrorAction SilentlyContinue)) {
        $maxFeedbackPerCycle = if ($Config.jules.PSObject.Properties.Name -contains "max_feedback_sessions_per_cycle") { [int]$Config.jules.max_feedback_sessions_per_cycle } else { 5 }
        $handled = 0
        Write-Host "[MONITOR] Pruefe ungetrackte Jules Sessions mit User-Feedback-Status..." -ForegroundColor Cyan
        try {
            $trackedIds = @($State.active_delegations | ForEach-Object { [string]$_.jules_session_id }) + @($State.active_pr_actions | ForEach-Object { [string]$_.jules_session_id })
            $sessions = @($allLiveJulesSessions | Sort-Object {
                $updatedAt = Get-JulesObjectPropertyValue -Object $_ -Name "updateTime"
                if ([string]::IsNullOrWhiteSpace([string]$updatedAt)) {
                    $updatedAt = Get-JulesObjectPropertyValue -Object $_ -Name "updatedAt"
                }
                try { [datetimeoffset]::Parse([string]$updatedAt).UtcDateTime } catch { [datetime]::MinValue }
            } -Descending)
            foreach ($session in $sessions) {
                if ($handled -ge $maxFeedbackPerCycle) { break }

                $julesState = [string](Get-JulesObjectPropertyValue -Object $session -Name "state")
                if ($julesState -ne "AWAITING_USER_FEEDBACK") { continue }

                $sessionName = [string](Get-JulesObjectPropertyValue -Object $session -Name "name")
                $sessionId = Resolve-JulesSessionId -SessionIdOrName $sessionName
                if ($trackedIds -contains $sessionId -or $trackedIds -contains $sessionName) { continue }

                $sessionRepo = Get-JulesSessionRepository -Session $session
                if (-not [string]::IsNullOrWhiteSpace($sessionRepo) -and $sessionRepo -ne $repo) { continue }

                Resolve-JulesAwaitingFeedback -State $State -Config $Config -Session $session -Repository $repo -DryRun:$DryRun
                $handled++
            }
            Write-Host "[MONITOR] Ungetrackte Jules Feedback-Sessions behandelt: $handled" -ForegroundColor DarkGray
        } catch {
            Write-Warning "[MONITOR] Ungetrackte Jules Sessions konnten nicht geprueft werden: $($_.Exception.Message)"
            Add-ErrorLog -State $State -Message "Untracked Jules feedback scan failed" -Context $_.Exception.Message
        }
    }

    # --- Step 2: Check open PRs for problems ---
    Write-Host "[MONITOR] Pruefe offene PRs auf Probleme..." -ForegroundColor Cyan

    try {
        $prsRaw = & gh pr list --repo $repo --state open --json number,title,headRefName,baseRefName,statusCheckRollup,mergeable --limit 100 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "gh pr list fehlgeschlagen: $($prsRaw | Out-String)"
        }
        $prs = @(($prsRaw | Out-String) | ConvertFrom-Json -ErrorAction Stop)

        $prActionsStarted = 0
        $maxPrActions = if ($Config.jules.PSObject.Properties.Name -contains "max_pr_actions_per_cycle") { [int]$Config.jules.max_pr_actions_per_cycle } elseif ($Config.jules.PSObject.Properties.Name -contains "max_pr_fix_sessions_per_cycle") { [int]$Config.jules.max_pr_fix_sessions_per_cycle } else { 2 }

        foreach ($pr in $prs) {
            $prNum = [int]$pr.number
            $mergeable = [string]$pr.mergeable

            # Check merge conflicts
            if ($mergeable -eq "CONFLICTING") {
                Write-Host ("[MONITOR]   PR #{0} MERGE CONFLICT!" -f $prNum) -ForegroundColor Red
                if ($prActionsStarted -lt $maxPrActions) {
                    if (Invoke-CliPrConflictResolution -State $State -QuotaRegistry $QuotaRegistry -JulesScriptDir $JulesScriptDir -Repository $repo -PullRequest $pr -DryRun:$DryRun) {
                        $prActionsStarted++
                    }
                }
            }

            # Check failing checks
            $statusCheckRollup = if ($pr.PSObject.Properties.Name -contains "statusCheckRollup") { @($pr.statusCheckRollup) } else { @() }
            $failingChecks = @($statusCheckRollup | Where-Object {
                $conclusion = if ($_.PSObject.Properties.Name -contains "conclusion") { [string]$_.conclusion } else { "" }
                $status = if ($_.PSObject.Properties.Name -contains "status") { [string]$_.status } else { "" }
                $state = if ($_.PSObject.Properties.Name -contains "state") { [string]$_.state } else { "" }
                $conclusion -in @("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED") -or
                $status -in @("FAILURE", "ERROR") -or
                $state -in @("FAILURE", "ERROR")
            })
            $pendingChecks = @($statusCheckRollup | Where-Object {
                $conclusion = if ($_.PSObject.Properties.Name -contains "conclusion") { [string]$_.conclusion } else { "" }
                $status = if ($_.PSObject.Properties.Name -contains "status") { [string]$_.status } else { "" }
                $state = if ($_.PSObject.Properties.Name -contains "state") { [string]$_.state } else { "" }
                ([string]::IsNullOrWhiteSpace($conclusion) -and -not [string]::IsNullOrWhiteSpace($status) -and $status -notin @("COMPLETED", "SUCCESS")) -or
                $state -eq "PENDING"
            })

            if ($failingChecks.Count -gt 0) {
                $failNames = ($failingChecks | ForEach-Object { $_.name }) -join ", "
                Write-Host ("[MONITOR]   PR #{0} {1} Checks fehlgeschlagen ({2})" -f $prNum, $failingChecks.Count, $failNames) -ForegroundColor Red
                if ($prActionsStarted -lt $maxPrActions -and $mergeable -ne "CONFLICTING") {
                    if (Add-JulesCheckFixComment -State $State -Repository $repo -PullRequest $pr -FailingChecks @($failingChecks | ForEach-Object { [string]($_.name) }) -DryRun:$DryRun) {
                        $prActionsStarted++
                    }
                }
            } elseif ($mergeable -eq "MERGEABLE" -and $pendingChecks.Count -eq 0) {
                $autoMergeEnabled = $Config.jules.PSObject.Properties.Name -contains "enable_auto_merge_ready_prs" -and [bool]$Config.jules.enable_auto_merge_ready_prs
                if ($autoMergeEnabled) {
                    Write-Host ("[MONITOR]   PR #{0} ist sauber; aktiviere Auto-Merge." -f $prNum) -ForegroundColor Green
                    if (-not $DryRun.IsPresent) {
                        $mergeResult = & gh pr merge $prNum --repo $repo --auto --squash 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Warning ("[MONITOR]   Auto-Merge fuer PR #{0} fehlgeschlagen: {1}" -f $prNum, ($mergeResult | Out-String))
                        }
                    }
                }
            }
        }
    } catch {
        Write-Warning "[MONITOR] PR-Check fehlgeschlagen: $_"
    }

    # --- Step 3: Process review queue ---
    $pendingReviews = @($State.review_queue | Where-Object { $_.review_status -eq "pending" })
    if ($pendingReviews.Count -gt 0) {
        Write-Host "[MONITOR] $($pendingReviews.Count) PRs im Review-Queue." -ForegroundColor Cyan

        foreach ($review in $pendingReviews) {
            if (-not $DryRun.IsPresent) {
                $review.review_status = "running"
                Save-AutopilotState -State $State
            }
            $reviewPrompt = Get-VorcePrReviewPrompt `
                -Repository $repo `
                -PullRequestNumber ([int]$review.pr_number) `
                -IssueNumber ([int]$review.issue_number) `
                -PullRequestUrl ([string]$review.pr_url)

            $reviewResult = Invoke-CliTask -QuotaRegistry $QuotaRegistry -TaskType "code_review" -DryRun:$DryRun -Prompt $reviewPrompt

            if ($reviewResult.success) {
                if (-not $DryRun.IsPresent) {
                    $review.review_status = "completed"
                }
                Write-Host "[MONITOR]   Review fuer PR #$($review.pr_number) abgeschlossen via $($reviewResult.provider)." -ForegroundColor Green

                # Post review result as PR comment
                if (-not $DryRun.IsPresent -and -not [string]::IsNullOrWhiteSpace($reviewResult.output)) {
                    Write-Host "[MONITOR]   Poste Review-Kommentar auf PR #$($review.pr_number)..." -ForegroundColor Gray
                    try {
                        $commentArgs = @("pr", "comment", [string]$review.pr_number, "--repo", $repo, "--body", $reviewResult.output)
                        $commentResult = & gh @commentArgs 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "[MONITOR]   Kommentar erfolgreich gepostet." -ForegroundColor Green
                        } else {
                            Write-Warning "[MONITOR]   Konnte Kommentar auf PR #$($review.pr_number) nicht posten: $($commentResult | Out-String)"
                        }
                    } catch {
                        Write-Warning "[MONITOR]   Konnte Kommentar auf PR #$($review.pr_number) nicht posten: $($_.Exception.Message)"
                    }
                }
            } else {
                if (-not $DryRun.IsPresent) {
                    $review.review_status = "pending"
                    Save-AutopilotState -State $State
                }
                Write-Host "[MONITOR]   Review fuer PR #$($review.pr_number) fehlgeschlagen." -ForegroundColor Red
            }
        }
    }

    # --- Step 4: Fill free Jules slots from planning backlog ---
    $maxConcurrentJules = [int]$Config.jules.max_concurrent_sessions
    $freeSlots = [Math]::Max(0, $maxConcurrentJules - $liveSessionLoad)
    $maxBacklogStarts = if ($Config.jules.PSObject.Properties.Name -contains "max_backlog_starts_per_monitoring_cycle") { [int]$Config.jules.max_backlog_starts_per_monitoring_cycle } else { 3 }
    $startedBacklog = 0
    if ($freeSlots -gt 0 -and $State.delegation_backlog.Count -gt 0) {
        Write-Host "[MONITOR] Jules freie Slots: $freeSlots; starte Backlog-Arbeit..." -ForegroundColor Cyan
        $remainingBacklog = @()
        foreach ($item in @($State.delegation_backlog)) {
            if ($startedBacklog -lt $freeSlots -and $startedBacklog -lt $maxBacklogStarts) {
                if (Start-JulesBacklogDelegation -State $State -QuotaRegistry $QuotaRegistry -JulesScriptDir $JulesScriptDir -Repository $repo -BacklogItem $item -DryRun:$DryRun) {
                    $startedBacklog++
                    continue
                }
            }
            $remainingBacklog += $item
        }
        if (-not $DryRun.IsPresent) {
            $State.delegation_backlog = @($remainingBacklog)
            Save-AutopilotState -State $State
        }
    }

    if (-not $DryRun.IsPresent) {
        $State.last_monitoring_at = (Get-Date -Format 'o')
        Save-AutopilotState -State $State
    }

    Write-Host "[MONITOR] ========== Monitoring abgeschlossen ==========" -ForegroundColor Blue
}
