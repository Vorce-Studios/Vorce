# Vorce-Autopilot/src/phases/monitoring-wakeup.ps1
# Monitoring Mode: Check running Jules sessions, PRs, merge conflicts

Set-StrictMode -Version Latest

function Test-MonitoringJulesCapacityState {
    param([AllowNull()][string]$State)

    $normalized = if ([string]::IsNullOrWhiteSpace($State)) { "QUEUED" } else { [string]$State }
    return $normalized -in @("QUEUED", "PLANNING", "IN_PROGRESS", "AWAITING_PLAN_APPROVAL")
}

function Sync-WorkingSessionsFromStatusFiles {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$VarDbDir
    )

    Confirm-WorkingSessionsState -State $State
    foreach ($workSession in @($State.working_sessions)) {
        $currentStatus = ([string]$workSession.status).ToUpperInvariant()
        if ($currentStatus -notin @("IN_PROGRESS", "RUNNING", "INITIALIZING")) { continue }

        $issueNum = [int]$workSession.issue_number
        $statusFile = Join-Path $VarDbDir "agent-tasks/$issueNum.json"
        if (Test-Path -LiteralPath $statusFile) {
            try {
                $agentState = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if (Test-ObjectProperty -Object $agentState -Name "status") {
                    $workSession.status = [string]$agentState.status
                    $workSession | Add-Member -MemberType NoteProperty -Name "last_checked_at" -Value (Get-Date -Format 'o') -Force
                    if (Test-ObjectProperty -Object $agentState -Name "error") {
                        $workSession | Add-Member -MemberType NoteProperty -Name "error" -Value ([string]$agentState.error) -Force
                    }
                    if (Test-ObjectProperty -Object $agentState -Name "updated_at") {
                        $workSession | Add-Member -MemberType NoteProperty -Name "status_updated_at" -Value ([string]$agentState.updated_at) -Force
                    }
                    if (Test-ObjectProperty -Object $agentState -Name "pr_url") {
                        $workSession | Add-Member -MemberType NoteProperty -Name "pr_url" -Value ([string]$agentState.pr_url) -Force
                    }
                    continue
                }
            } catch {
                Write-Warning "[MONITOR] Working Session #$issueNum Statusfile konnte nicht gelesen werden: $_"
            }
        }

        if (Test-ObjectProperty -Object $workSession -Name "process_id" -and $workSession.process_id) {
            $proc = Get-Process -Id ([int]$workSession.process_id) -ErrorAction SilentlyContinue
            if ($null -eq $proc) {
                $workSession.status = "FAILED"
                $workSession | Add-Member -MemberType NoteProperty -Name "last_checked_at" -Value (Get-Date -Format 'o') -Force
                $workSession | Add-Member -MemberType NoteProperty -Name "error" -Value "Local agent process exited before writing a final status." -Force
                $failedState = [pscustomobject]@{
                    status = "FAILED"
                    pr_url = ""
                    updated_at = (Get-Date -Format 'o')
                    error = "Local agent process exited before writing a final status."
                }
                Write-JsonLocked -Path $statusFile -Data $failedState | Out-Null
                Write-Host "[MONITOR] Working Session #$issueNum als FAILED markiert: PID $($workSession.process_id) laeuft nicht mehr." -ForegroundColor Yellow
            }
        }
    }
}

function Start-QueuedWorkingSessions {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Repository,
        [switch]$DryRun
    )

    Confirm-WorkingSessionsState -State $State
    $ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../..")
    $toolsDir = Join-Path $ScriptDir "tools"
    $quotaRegistryPath = Join-Path $ScriptDir "var/db/quota-registry.json"
    $VarDbDir = Join-Path $ScriptDir "var/db"
    Sync-WorkingSessionsFromStatusFiles -State $State -VarDbDir $VarDbDir

    $workingCfg = if (Test-ObjectProperty -Object $Config -Name "working_sessions") { $Config.working_sessions } else { $null }
    if ($workingCfg -and (Test-ObjectProperty -Object $workingCfg -Name "enabled") -and -not $workingCfg.enabled) {
        return
    }

    $maxConcurrent = if ($workingCfg -and (Test-ObjectProperty -Object $workingCfg -Name "max_concurrent")) { [int]$workingCfg.max_concurrent } else { 3 }
    if ($maxConcurrent -le 0) { return }

    $running = @($State.working_sessions | Where-Object { [string]$_.status -eq "IN_PROGRESS" }).Count
    $slots = $maxConcurrent - $running
    if ($slots -le 0 -or @($State.working_queue).Count -eq 0) { return }

    $toStart = @($State.working_queue | Select-Object -First $slots)
    foreach ($item in $toStart) {
        $issueNum = [int]$item.issue_number
        $issueTitle = [string]$item.issue_title
        $agentProvider = [string]$item.agent_provider

        if ($DryRun.IsPresent) {
            Write-Host "[MONITOR] [DRY RUN] Wuerde Working Session starten: #$issueNum -> $agentProvider" -ForegroundColor DarkYellow
            continue
        }

        try {
            $cmdArgs = "-NoExit", "-File", "`"$toolsDir\run-visible-agent-task.ps1`"", "-IssueNumber", $issueNum, "-IssueTitle", "`"$issueTitle`"", "-AgentProvider", "`"$agentProvider`"", "-Repository", "`"$Repository`"", "-QuotaRegistryPath", "`"$quotaRegistryPath`""
            $proc = Start-Process pwsh -ArgumentList $cmdArgs -PassThru -WindowStyle Normal

            $State.working_sessions += @([ordered]@{
                id             = if (Test-ObjectProperty -Object $item -Name "id") { $item.id } else { "work-$issueNum-$($proc.Id)" }
                issue_number   = $issueNum
                issue_title    = $issueTitle
                agent_provider = $agentProvider
                process_id     = $proc.Id
                status         = "IN_PROGRESS"
                started_at     = (Get-Date -Format 'o')
            })
            $State.working_queue = @($State.working_queue | Where-Object { [int]$_.issue_number -ne $issueNum })
            Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "local-agent-$($proc.Id)" -AgentType $agentProvider -JobId $($proc.Id.ToString())
            Write-Host "[MONITOR] Working Session gestartet: #$issueNum -> $agentProvider (PID: $($proc.Id))" -ForegroundColor Cyan
        } catch {
            Write-Warning "[MONITOR] Working Session fuer #$issueNum fehlgeschlagen: $_"
            Add-ErrorLog -State $State -Message "Working session failed for #$issueNum" -Context $_.Exception.Message
        }
    }

    Save-AutopilotState -State $State
}

function Add-DecisionPending {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Topic,
        [Parameter(Mandatory)][string]$Context
    )

    $exists = $State.decisions_pending | Where-Object { $_.topic -eq $Topic }
    if (-not $exists) {
        $State.decisions_pending += @([ordered]@{
            topic      = $Topic
            context    = $Context
            created_at = (Get-Date -Format 'o')
        })
        Write-Host "[MONITOR] Entscheidung hinzugefuegt: $Topic" -ForegroundColor Yellow
    } else {
        Write-Host "[MONITOR] Entscheidung existiert bereits: $Topic (uebersprungen)" -ForegroundColor DarkGray
    }
}

function Get-ReviewOutputText {
    param([AllowNull()][string]$RawOutput)

    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return "" }
    try {
        $json = $RawOutput | ConvertFrom-Json -ErrorAction Stop
        foreach ($field in @("result", "response", "output", "message", "text")) {
            if ((Test-ObjectProperty -Object $json -Name $field) -and -not [string]::IsNullOrWhiteSpace([string]$json.$field)) {
                return [string]$json.$field
            }
        }
    } catch {}
    return [string]$RawOutput
}

function ConvertTo-PrReviewDecision {
    param([AllowNull()][string]$RawOutput)

    $text = Get-ReviewOutputText -RawOutput $RawOutput
    $decision = "REQUEST_CHANGES"
    $summary = $text.Trim()
    $findings = @()

    try {
        $jsonText = $text
        $match = [regex]::Match($text, '(?s)\{.*\}')
        if ($match.Success) { $jsonText = $match.Value }
        $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop
        if ((Test-ObjectProperty -Object $parsed -Name "decision") -and [string]$parsed.decision -match "APPROVE|PASS") {
            $decision = "APPROVE"
        }
        if ((Test-ObjectProperty -Object $parsed -Name "summary") -and -not [string]::IsNullOrWhiteSpace([string]$parsed.summary)) {
            $summary = [string]$parsed.summary
        }
        if (Test-ObjectProperty -Object $parsed -Name "findings") {
            $findings = @($parsed.findings)
        }
    } catch {
        if ($text -match "(?i)\b(APPROVE|PASS|LGTM)\b" -and $text -notmatch "(?i)\b(REQUEST_CHANGES|REJECT|BLOCK|FAIL)\b") {
            $decision = "APPROVE"
        }
    }

    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = if ($decision -eq "APPROVE") { "Claude Code Review: keine blockierenden Probleme gefunden." } else { "Claude Code Review: keine auswertbare Freigabe erhalten." }
    }
    if ($summary.Length -gt 1800) { $summary = $summary.Substring(0, 1800) + "..." }

    return [pscustomobject]@{
        decision = $decision
        summary  = $summary
        findings = $findings
    }
}

function Get-CeoPrReviewType {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$PullRequest,
        [switch]$DryRun
    )

    if ($DryRun.IsPresent) { return "simple_review" }
    $prNum = [int]$PullRequest.number
    $checkCount = if (Test-ObjectProperty -Object $PullRequest -Name "statusCheckRollup") { @($PullRequest.statusCheckRollup).Count } else { 0 }
    $prompt = @"
Entscheide fuer PR #$prNum, ob Claude Code ein einfaches Review oder ein ausfuehrliches Review machen soll.
Antworte nur als JSON: {"review_type":"simple_review|complex_review","reason":"kurzer Fakt"}

Kriterien:
- complex_review: Merge-Konflikte, CI-Fehler, Architektur-/Rust-Core-Aenderungen, viele Dateien, Sicherheits-/Build-Risiko.
- simple_review: kleine isolierte Docs/Scripts/UI-Korrektur ohne CI-Risiko.

PR: $($PullRequest.title)
Mergeable: $($PullRequest.mergeable)
Checks: $checkCount
"@

    try {
        $result = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "qa_disposition" -Prompt $prompt -State $State -DryRun:$DryRun
        if ($result.success) {
            $text = Get-ReviewOutputText -RawOutput ([string]$result.output)
            $match = [regex]::Match($text, '(?s)\{.*\}')
            $jsonText = if ($match.Success) { $match.Value } else { $text }
            $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop
            if ((Test-ObjectProperty -Object $parsed -Name "review_type") -and [string]$parsed.review_type -in @("simple_review", "complex_review")) {
                return [string]$parsed.review_type
            }
        }
    } catch {
        Write-Warning "[MONITOR] CEO Review-Typ fuer PR #$prNum nicht auswertbar: $_"
    }

    if ([string]$PullRequest.mergeable -eq "CONFLICTING" -or $checkCount -gt 4) { return "complex_review" }
    return "simple_review"
}

function Invoke-ClaudePrReviewSession {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][object]$ReviewItem,
        [Parameter(Mandatory)][string]$ReviewType,
        [switch]$DryRun
    )

    $depthText = if ($ReviewType -eq "complex_review") { "ausfuehrliches Review mit Fokus auf Regressionen, Architektur, Rust-Sicherheit, Tests und CI" } else { "einfaches Review mit Fokus auf offensichtliche Fehler, Build-Risiko und Akzeptanzkriterien" }
    $prompt = @"
Du bist Claude Code und fuehrst ein PR-Review fuer Vorce aus.
Beschraenke dich auf Fakten, betroffene Dateien/Zeilen, konkrete Risiken und klare Entscheidung. Kein Smalltalk.

Repository: $Repository
PR: #$($ReviewItem.pr_number)
Issue: #$($ReviewItem.issue_number)
Review-Typ: $ReviewType ($depthText)

Arbeite selbststaendig mit gh/git, aber veraendere keine Dateien.
Pruefe Diff, CI-Status, offensichtliche Tests und Akzeptanzrisiken.

Antworte ausschliesslich als JSON:
{
  "decision": "APPROVE|REQUEST_CHANGES",
  "summary": "kurze deutsche Zusammenfassung",
  "findings": [
    {"severity":"blocker|major|minor", "file":"pfad oder leer", "line":0, "message":"konkreter Befund"}
  ]
}
"@

    return Invoke-CliTask `
        -QuotaRegistry $QuotaRegistry `
        -TaskType $ReviewType `
        -Prompt $prompt `
        -WorkingDirectory (Resolve-Path (Join-Path $PSScriptRoot "../../..")) `
        -ProviderOverride "claude_code" `
        -ModelTierOverride "balanced" `
        -DryRun:$DryRun
}

function Set-GitHubPrReviewDecision {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$Decision,
        [Parameter(Mandatory)][string]$Body,
        [switch]$DryRun
    )

    if ($DryRun.IsPresent) { return }
    $safeBody = if ([string]::IsNullOrWhiteSpace($Body)) { "Claude Code Review abgeschlossen." } else { $Body }
    if ($Decision -eq "APPROVE") {
        $reviewOut = gh pr review $PullRequestNumber --repo $Repository --approve --body $safeBody 2>&1
        if ($LASTEXITCODE -ne 0) { throw "GitHub APPROVE Review fuer PR #$PullRequestNumber fehlgeschlagen: $reviewOut" }
        try { gh label create "status: ready-to-merge" --repo $Repository --color "2EA043" --description "Claude Code Review approved by Autopilot" 2>&1 | Out-Null } catch {}
        gh pr edit $PullRequestNumber --repo $Repository --remove-label "status: needs-review" 2>&1 | Out-Null
        gh pr edit $PullRequestNumber --repo $Repository --add-label "status: ready-to-merge" 2>&1 | Out-Null
    } else {
        $reviewOut = gh pr review $PullRequestNumber --repo $Repository --request-changes --body $safeBody 2>&1
        if ($LASTEXITCODE -ne 0) { throw "GitHub REQUEST_CHANGES Review fuer PR #$PullRequestNumber fehlgeschlagen: $reviewOut" }
        try { gh label create "status: needs-review" --repo $Repository --color "D29922" --description "Claude Code Review requested changes" 2>&1 | Out-Null } catch {}
        gh pr edit $PullRequestNumber --repo $Repository --remove-label "status: ready-to-merge" 2>&1 | Out-Null
        gh pr edit $PullRequestNumber --repo $Repository --add-label "status: needs-review" 2>&1 | Out-Null
    }
}

function Get-MonitoringLabelNames {
    param([AllowNull()][object]$Issue)

    if ($null -eq $Issue -or -not (Test-ObjectProperty -Object $Issue -Name "labels") -or $null -eq $Issue.labels) {
        return @()
    }

    return @($Issue.labels | ForEach-Object {
        if ($_ -is [string]) { $_ } elseif (Test-ObjectProperty -Object $_ -Name "name") { [string]$_.name }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Add-MonitoringWorkingQueueItem {
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
        Write-Host "[MONITOR] Working Session fuer Issue #$IssueNumber ist bereits geplant." -ForegroundColor DarkGray
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
    Write-Host "[MONITOR] Working Session geplant: Issue #$IssueNumber -> $AgentProvider" -ForegroundColor Cyan
}

function Get-MonitoringJulesSafetyReason {
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

function Test-MonitoringJulesIssueSafe {
    param(
        [AllowNull()][string]$Title,
        [AllowNull()][string]$Body
    )

    return [string]::IsNullOrWhiteSpace((Get-MonitoringJulesSafetyReason -Title $Title -Body $Body))
}

function Test-MonitoringLocalCliIssue {
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

function Test-MonitoringIssueHasJulesSession {
    param([AllowNull()][object]$Issue)

    if ($null -eq $Issue) { return $false }
    $body = if ((Test-ObjectProperty -Object $Issue -Name "body") -and $null -ne $Issue.body) { [string]$Issue.body } else { "" }
    return (
        $body -match "<!--\s*jules-session-id:" -or
        $body -match "<!--\s*jules-session-name:" -or
        $body -match "<!--\s*vorce-queue-state:\s*dispatched"
    )
}

function Get-MonitoringSessionId {
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

function Import-StalledJulesSessions {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$SessionCachePath,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $SessionCachePath)) { return }

    $sessions = @()
    try {
        $sessions = @(Get-Content -LiteralPath $SessionCachePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Warning "[MONITOR] Konnte Jules Session Cache nicht lesen: $_"
        return
    }

    $activeIssueNumbers = @($State.active_delegations | Where-Object {
        -not (Test-ObjectProperty -Object $_ -Name "agent_type") -or [string]$_.agent_type -eq "jules"
    } | ForEach-Object { [int]$_.issue_number })

    foreach ($session in $sessions) {
        $stateName = if (Test-ObjectProperty -Object $session -Name "state") { [string]$session.state } else { "" }
        if ($stateName -notin @("AWAITING_USER_FEEDBACK", "PAUSED", "FAILED")) { continue }
        if ((Test-ObjectProperty -Object $session -Name "repo") -and -not [string]::IsNullOrWhiteSpace([string]$session.repo) -and [string]$session.repo -ne $Repository) { continue }
        if (-not (Test-ObjectProperty -Object $session -Name "issueNumber") -or $null -eq $session.issueNumber) {
            $sessionTitle = if (Test-ObjectProperty -Object $session -Name "title") { [string]$session.title } else { "(ohne Titel)" }
            if ($DryRun.IsPresent) {
                Write-Host "[MONITOR] [DRY RUN] Unzugeordnete haengende Jules Session gefunden: $sessionTitle ($stateName)" -ForegroundColor DarkYellow
            } else {
                Add-DecisionPending -State $State -Topic "Unzugeordnete Jules Session braucht Klärung" -Context "Session '$sessionTitle' ($stateName) hat keine Issue-Nummer und kann nicht automatisch sauber weitergefuehrt werden. URL: $($session.url)"
            }
            continue
        }

        $issueNum = [int]$session.issueNumber
        if ($activeIssueNumbers -contains $issueNum) { continue }

        $sessionTitle = if (Test-ObjectProperty -Object $session -Name "title") { [string]$session.title } else { "Issue #$issueNum" }
        if ($sessionTitle -match "_MAIs_" -or $sessionTitle -match "Resolve-Merge-Conflicts?") {
            if ($DryRun.IsPresent) {
                Write-Host "[MONITOR] [DRY RUN] Haengende Jules Session #$issueNum wegen unsicherem Scope blockiert." -ForegroundColor DarkYellow
            } else {
                Add-DecisionPending -State $State -Topic "Jules Session #$issueNum blockiert durch unsicheren Scope" -Context "Session fuer Issue #$issueNum ist '$stateName', wird aber nicht automatisch neu gestartet/weitergetrieben, weil Titel/Scope nach Master-, Tracker- oder Konfliktauftrag aussieht. URL: $($session.url)"
            }
            continue
        }

        $sessionId = Get-MonitoringSessionId -Session $session
        if ([string]::IsNullOrWhiteSpace($sessionId)) { continue }

        if ($DryRun.IsPresent) {
            Write-Host "[MONITOR] [DRY RUN] Wuerde haengende Jules Session fuer Issue #$issueNum importieren ($stateName)." -ForegroundColor DarkYellow
            continue
        }

        Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $sessionTitle -JulesSessionId $sessionId -AgentType "jules"
        Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $stateName
        Write-Host "[MONITOR] Importierte haengende Jules Session fuer Issue #$issueNum ($stateName)." -ForegroundColor Yellow
    }
}

function Start-JulesRefill {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$VarDbDir,
        [switch]$DryRun
    )

    if (-not (Test-ObjectProperty -Object $Config -Name "jules") -or -not (Test-ObjectProperty -Object $Config.jules -Name "monitoring_refill_enabled") -or -not [bool]$Config.jules.monitoring_refill_enabled) {
        return
    }

    $julesProvider = $QuotaRegistry.providers.jules
    $usage = $julesProvider.usage_today
    $maxConcurrent = [int]$Config.jules.max_concurrent_sessions
    $maxDaily = [int]$Config.jules.max_daily_sessions
    $callsToday = if (Test-ObjectProperty -Object $usage -Name "calls") { [int]$usage.calls } else { 0 }

    $trackedLive = @($State.active_delegations | Where-Object {
        (-not (Test-ObjectProperty -Object $_ -Name "agent_type") -or [string]$_.agent_type -eq "jules") -and
        (Test-MonitoringJulesCapacityState -State $(if (Test-ObjectProperty -Object $_ -Name "jules_state") { [string]$_.jules_state } else { "QUEUED" }))
    }).Count
    $apiLive = if (Test-ObjectProperty -Object $usage -Name "scoped_live_capacity_sessions") { [int]$usage.scoped_live_capacity_sessions } elseif (Test-ObjectProperty -Object $usage -Name "live_capacity_sessions") { [int]$usage.live_capacity_sessions } else { 0 }
    $liveCount = [Math]::Max($trackedLive, $apiLive)
    $slots = [Math]::Min($maxConcurrent - $liveCount, $maxDaily - $callsToday)
    if ($slots -le 0) {
        Write-Host "[MONITOR] Jules Refill: keine freien Slots (live=$liveCount, daily=$callsToday/$maxDaily)." -ForegroundColor DarkGray
        return
    }

    $issues = @()
    $cachedIssuePath = Join-Path $VarDbDir "github-issues.json"
    if (Test-Path -LiteralPath $cachedIssuePath) {
        try { $issues = @(Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object { $_.repo -eq $Repository -and $_.state -eq "OPEN" }) } catch { $issues = @() }
    }
    if ($issues.Count -eq 0) {
        try { $issues = @(Get-GitHubIssues -Repository $Repository -Limit 100) } catch { $issues = @() }
    }

    $activeIssueNumbers = @($State.active_delegations | ForEach-Object { [int]$_.issue_number })
    $candidates = @()
    foreach ($issue in @($issues | Sort-Object @{ Expression = { [int]$_.number } })) {
        $labels = @(Get-MonitoringLabelNames -Issue $issue)
        $hasJulesLabel = ($labels -contains "jules-task") -or ($labels -contains "Todo-UserISU")
        $hasExcludedStatus = @($labels | Where-Object { $_ -in @("status: in-progress", "status: needs-review", "status: needs-testing", "status: blocked", "status: ready-to-merge", "duplicate", "wontfix", "on-hold") }).Count -gt 0
        $hasOtherAgent = @($labels | Where-Object { $_ -match "^agent:" -and $_ -ne "agent:jules" }).Count -gt 0
        $issueNum = [int]$issue.number
        $title = [string]$issue.title
        $body = if ((Test-ObjectProperty -Object $issue -Name "body") -and $null -ne $issue.body) { [string]$issue.body } else { "" }
        $hasJulesSessionMarker = Test-MonitoringIssueHasJulesSession -Issue $issue

        if (-not $hasJulesLabel) { continue }
        if ($hasExcludedStatus -or $hasOtherAgent -or ($activeIssueNumbers -contains $issueNum)) {
            continue
        }

        $unsafeReason = Get-MonitoringJulesSafetyReason -Title $title -Body $body
        if ([string]::IsNullOrWhiteSpace($unsafeReason)) {
            if ($hasJulesSessionMarker) {
                Write-Host "[MONITOR] Jules-Task #$issueNum uebersprungen: vorhandene Jules-Session wird nicht dupliziert." -ForegroundColor DarkGray
                continue
            }
            $candidates += @($issue)
            continue
        }

        if (Test-MonitoringLocalCliIssue -Title $title -Body $body) {
            if ($DryRun.IsPresent) {
                Write-Host "[MONITOR] [DRY RUN] Wuerde unsicheren Jules-Task #$issueNum lokal einplanen: $unsafeReason" -ForegroundColor DarkYellow
            } else {
                Add-MonitoringWorkingQueueItem -State $State -IssueNumber $issueNum -IssueTitle $title -AgentProvider "gemini_cli"
                Write-Host "[MONITOR] Jules-Task #$issueNum zu lokaler CLI-Queue umgebogen: $unsafeReason" -ForegroundColor Yellow
            }
            continue
        }

        Write-Host "[MONITOR] Jules-Task #$issueNum blockiert: $unsafeReason" -ForegroundColor Yellow
    }

    if ($candidates.Count -eq 0) {
        Write-Host "[MONITOR] Jules Refill: freie Slots vorhanden, aber keine sicheren Jules-Kandidaten gefunden." -ForegroundColor Yellow
        if (-not $DryRun.IsPresent) {
            Save-AutopilotState -State $State
        }
        return
    }

    foreach ($issue in @($candidates | Select-Object -First $slots)) {
        $issueNum = [int]$issue.number
        $issueTitle = [string]$issue.title
        if ($DryRun.IsPresent) {
            Write-Host "[MONITOR] [DRY RUN] Wuerde Jules Refill starten: Issue #$issueNum - $issueTitle" -ForegroundColor DarkYellow
            continue
        }

        try {
            $sessionId = New-JulesSession -IssueNumber $issueNum -Repository $Repository -ApiKey $env:JULES_API_KEY -AutoCreatePr
            Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId $sessionId -AgentType "jules"
            Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
            Write-Host "[MONITOR] Jules Refill gestartet: Issue #$issueNum -> Session $sessionId" -ForegroundColor Green
        } catch {
            Write-Warning "[MONITOR] Monitoring Jules refill failed for #${issueNum}: $_"
            Add-ErrorLog -State $State -Message "Monitoring Jules refill failed for #$issueNum" -Context $_.Exception.Message
        }
    }
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
    $State = Update-AutopilotStateObject -State $State
    Confirm-WorkingSessionsState -State $State
    $monitoringStartedAt = Get-Date
    $monitoringQueueBefore = @($State.working_queue).Count
    $monitoringDelegationsBefore = @($State.active_delegations).Count
    $monitoringDecisionsBefore = @($State.decisions_pending).Count

    $ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../..")
    $VarDbDir = Join-Path $ScriptDir "var/db"
    $sessionCachePath = Join-Path $VarDbDir "jules-sessions.json"
    if (-not (Test-Path -LiteralPath $sessionCachePath)) {
        $dashboardSessionCachePath = Join-Path $ScriptDir "dashboard/jules-sessions.json"
        if (Test-Path -LiteralPath $dashboardSessionCachePath) {
            $sessionCachePath = $dashboardSessionCachePath
        }
    }
    Import-StalledJulesSessions -State $State -Repository $repo -SessionCachePath $sessionCachePath -DryRun:$DryRun

    # --- Step 1: Fetch Open PRs ---
    Write-Host "[MONITOR] Pruefe offene PRs..." -ForegroundColor Cyan
    $prs = @()
    $conflictingPrs = @()

    # Use cached PR data from the dashboard instead of calling GitHub directly
    $cachedPrPath = Join-Path $VarDbDir "pull-requests.json"
    $prsRaw = $null
    if (Test-Path $cachedPrPath) {
        try {
            $prsRaw = Get-Content -LiteralPath $cachedPrPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warning "[MONITOR] Fehler beim Lesen der gecachten PRs: $_"
        }
    }

    try {
        if ($null -ne $prsRaw -and ($prsRaw -is [System.Array] -or $prsRaw -is [System.Collections.IList])) {
            $prs = @($prsRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo })
            Write-Host "[MONITOR] Gecachte PR-Daten erfolgreich geladen ($($prs.Count) offene PRs)." -ForegroundColor DarkGray
        } else {
            Write-Host "[MONITOR] Lade PRs direkt via gh-cli (Fallback)..." -ForegroundColor DarkGray
            # Safe encapsulation from github-client wrapper
            $prs = Get-GitHubPullRequests -Repository $repo -Limit 100
        }

        # --- Step 1.2: Run Monitoring Sequence (Session Splitting) ---
        if ($Config.PSObject.Properties.Name -contains "monitoring_sequence") {
            Write-Host "[MONITOR] Starte sequentielle Monitoring-Sequenz..." -ForegroundColor Yellow
            $monitoringContext = ""
            $prsData = $prs | ConvertTo-Json -Depth 3
            $sessionsData = $State.active_delegations | ConvertTo-Json -Depth 3

            foreach ($step in $Config.monitoring_sequence) {
                Write-Host "[MONITOR] Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan
                $promptVars = @{ repo = $repo; prs = $prsData; sessions = $sessionsData; context = $monitoringContext }
                $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
                $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

                $stepResult = Invoke-DualCeoTask `
                    -QuotaRegistry $QuotaRegistry `
                    -Config $Config `
                    -TaskType "monitoring" `
                    -DryRun:$DryRun `
                    -Prompt $fullPrompt `
                    -State $State

                if ($stepResult.success) {
                    $monitoringContext += "`n### Ergebnis $($step.label):`n$($stepResult.output)`n"
                } else {
                    Write-Warning "[MONITOR] Schritt $($step.label) fehlgeschlagen: $($stepResult.output)"
                }
            }
        }

        foreach ($pr in $prs) {
            $prNum = [int]$pr.number
            $mergeable = [string]$pr.mergeable

            if ($mergeable -eq "CONFLICTING") {
                Write-Host ("[MONITOR]   PR #{0} MERGE CONFLICT!" -f $prNum) -ForegroundColor Red
                $conflictingPrs += $pr
            }

            $failingChecks = @()
            $checks = if (Test-ObjectProperty -Object $pr -Name "statusCheckRollup") { $pr.statusCheckRollup } else { @() }
            if ($checks) {
                $failingChecks = @($checks | Where-Object {
                    ((Test-ObjectProperty -Object $_ -Name "conclusion") -and $_.conclusion -eq "FAILURE") -or
                    ((Test-ObjectProperty -Object $_ -Name "status") -and $_.status -eq "FAILURE")
                })
            }

            if ($failingChecks.Count -gt 0) {
                $failNames = ($failingChecks | ForEach-Object { $_.name }) -join ", "
                Write-Host ("[MONITOR]   PR #{0} {1} Checks fehlgeschlagen ({2})" -f $prNum, $failingChecks.Count, $failNames) -ForegroundColor Red
            }

            $prUrl = if (Test-ObjectProperty -Object $pr -Name "url") { [string]$pr.url } else { "https://github.com/$repo/pull/$prNum" }
            $alreadyReviewed = @($State.review_queue | Where-Object {
                (Test-ObjectProperty -Object $_ -Name "pr_number") -and
                [int]$_.pr_number -eq $prNum -and
                (Test-ObjectProperty -Object $_ -Name "review_status") -and
                [string]$_.review_status -in @("pending", "in_progress", "approved")
            }).Count -gt 0
            $isDraft = if (Test-ObjectProperty -Object $pr -Name "isDraft") { [bool]$pr.isDraft } else { $false }
            if (-not $alreadyReviewed -and -not $isDraft) {
                if ($DryRun.IsPresent) {
                    Write-Host "[MONITOR] [DRY RUN] Wuerde PR #$prNum in Claude-Code Review-Queue aufnehmen." -ForegroundColor DarkYellow
                } else {
                    Add-ReviewItem -State $State -IssueNumber 0 -PrUrl $prUrl -PrNumber $prNum
                    Write-Host "[MONITOR]   PR #$prNum in Claude-Code Review-Queue aufgenommen." -ForegroundColor Cyan
                }
            }
        }
    } catch {
        Write-Warning "[MONITOR] PR-Check fehlgeschlagen: $_"
    }

    # --- Step 1b: Spawn queued Working Sessions ---
    Start-QueuedWorkingSessions -State $State -Config $Config -Repository $repo -DryRun:$DryRun

    # --- Step 2: Check active Jules sessions ---
    Write-Host "[MONITOR] Pruefe $($State.active_delegations.Count) aktive Delegierungen..." -ForegroundColor Cyan

    foreach ($delegation in $State.active_delegations) {
        $issueNum = [int]$delegation.issue_number
        $sessionId = [string]$delegation.jules_session_id

        if ($sessionId -match "^dry-run") {
            Write-Host ("[MONITOR]   #{0} [DRY RUN] Ueberspringe." -f $issueNum) -ForegroundColor DarkGray
            continue
        }

        $agentType = if ($delegation.PSObject.Properties.Name -contains "agent_type" -and $delegation.agent_type) { [string]$delegation.agent_type } else { "jules" }
        if ($sessionId -match "^local-agent-" -and $agentType -eq "jules") {
            $agentType = "local_agent"
        }

        # --- Stalled-Session-Detection (45 min Timeout) ---
        $delegatedAtStr = $delegation.delegated_at
        if (-not [string]::IsNullOrWhiteSpace($delegatedAtStr)) {
            try {
                $delegatedAt = [datetimeoffset]::Parse($delegatedAtStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $timeSinceDelegation = (Get-Date) - $delegatedAt.LocalDateTime
                if ($timeSinceDelegation.TotalMinutes -ge 45) {
                    Write-Host ("[MONITOR]   #{0} (Agent: {1}): Stalled-Session erkannt ({2:N0} min)! Eskaliere sofort." -f $issueNum, $agentType, $timeSinceDelegation.TotalMinutes) -ForegroundColor Red
                    Add-ErrorLog -State $State -Message "Stalled session detected for #$issueNum (>45min)" -Context "Session: $sessionId, Agent: $agentType"

                    if (-not $DryRun.IsPresent) {
                        Set-DelegationEscalation -State $State -IssueNumber $issueNum -Reason "STALLED_TIMEOUT"
                    } else {
                        Complete-Delegation -State $State -IssueNumber $issueNum -Result "failed_timeout"
                    }
                    continue
                }
            } catch {
                Write-Warning "[MONITOR] Could not parse delegated_at: $delegatedAtStr"
            }
        }

        if ($agentType -eq "jules") {
            try {
                # Safe wrapping using jules-client status wrapper
                $session = Get-JulesSessionStatus -SessionId $sessionId -ApiKey $env:JULES_API_KEY
                if ($null -eq $session) {
                    throw "Session $sessionId konnte nicht geladen werden."
                }
                $julesState = [string]$session.state

                Write-Host ("[MONITOR]   #{0} ({1}): {2} (Agent: jules)" -f $issueNum, $sessionId, $julesState) -ForegroundColor $(
                    switch ($julesState) {
                        "COMPLETED"  { "Green" }
                        "IN_PROGRESS" { "Cyan" }
                        "QUEUED"     { "DarkGray" }
                        "PLANNING"   { "Cyan" }
                        default      { "Yellow" }
                    }
                )

                Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $julesState

                # Find matching PR for this session
                $matchingPr = $prs | Where-Object { $_.title -match "#$issueNum" -or $_.headRefName -match "$issueNum" } | Select-Object -First 1

                switch ($julesState) {
                    "COMPLETED" {
                        $prUrl = Get-JulesSessionPullRequestUrl -Session $session
                        if (-not [string]::IsNullOrWhiteSpace($prUrl)) {
                            Write-Host "[MONITOR]   -> PR gefunden: $prUrl" -ForegroundColor Green
                            Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $julesState -PrUrl $prUrl
                            $prNumber = if ($prUrl -match '/pull/(\d+)') { [int]$Matches[1] } else { 0 }

                            Add-ReviewItem -State $State -IssueNumber $issueNum -PrUrl $prUrl -PrNumber $prNumber
                        }
                        Complete-Delegation -State $State -IssueNumber $issueNum -Result "completed"
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
                            if (-not $DryRun.IsPresent) {
                                Send-JulesMessage -SessionIdOrName $sessionId -Message "Continue with the task. If blocked, skip the problematic step and proceed." -ApiKey $env:JULES_API_KEY
                            }
                            $delegation.retry_count = $retryCount + 1
                        } else {
                            Write-Host "[MONITOR]   -> ESKALATION: Re-Planning / Fehlerbehebung erforderlich!" -ForegroundColor Red
                            if (-not $DryRun.IsPresent) {
                                Set-DelegationEscalation -State $State -IssueNumber $issueNum -Reason "FEEDBACK_TIMEOUT_CI_OR_BLOCKER"
                            }
                        }
                    }
                    "FAILED" {
                        Write-Host "[MONITOR]   -> FAILED! Logge Fehler und eskaliere." -ForegroundColor Red
                        Add-ErrorLog -State $State -Message "Jules session failed for #$issueNum" -Context "Session: $sessionId"
                        if (-not $DryRun.IsPresent) {
                            Set-DelegationEscalation -State $State -IssueNumber $issueNum -Reason "FAILED"
                        } else {
                            Complete-Delegation -State $State -IssueNumber $issueNum -Result "failed"
                        }
                    }
                }
            } catch {
                Write-Warning ("[MONITOR]   #{0} API-Fehler: {1}" -f $issueNum, $_)
                Add-ErrorLog -State $State -Message "API error for #$issueNum" -Context $_.Exception.Message
            }
        } else {
            # Check local CLI agent status file (stored inside var/db)
            $statusFile = Join-Path $VarDbDir "agent-tasks/$issueNum.json"
            if (Test-Path $statusFile) {
                try {
                    $agentState = Get-Content $statusFile -Raw | ConvertFrom-Json
                    $currentState = $agentState.status

                    Write-Host ("[MONITOR]   #{0} (Local Agent: {1}): {2}" -f $issueNum, $agentType, $currentState) -ForegroundColor $(
                        switch ($currentState) {
                            "COMPLETED"   { "Green" }
                            "IN_PROGRESS" { "Cyan" }
                            "FAILED"      { "Red" }
                            default       { "Yellow" }
                        }
                    )

                    Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $currentState
                    foreach ($workSession in $State.working_sessions) {
                        if ([int]$workSession.issue_number -eq $issueNum) {
                            $workSession.status = $currentState
                            $workSession | Add-Member -MemberType NoteProperty -Name "last_checked_at" -Value (Get-Date -Format 'o') -Force
                            if (Test-ObjectProperty -Object $agentState -Name "error") {
                                $workSession | Add-Member -MemberType NoteProperty -Name "error" -Value ([string]$agentState.error) -Force
                            }
                            if (Test-ObjectProperty -Object $agentState -Name "updated_at") {
                                $workSession | Add-Member -MemberType NoteProperty -Name "status_updated_at" -Value ([string]$agentState.updated_at) -Force
                            }
                            if (Test-ObjectProperty -Object $agentState -Name "pr_url") {
                                $workSession | Add-Member -MemberType NoteProperty -Name "pr_url" -Value ([string]$agentState.pr_url) -Force
                            }
                            break
                        }
                    }

                    if ($currentState -eq "COMPLETED") {
                        if ($agentState.pr_url -and -not [string]::IsNullOrWhiteSpace($agentState.pr_url)) {
                            $prUrl = $agentState.pr_url
                            Write-Host "[MONITOR]   -> Local PR gefunden: $prUrl" -ForegroundColor Green
                            Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $currentState -PrUrl $prUrl
                            $prNumber = if ($prUrl -match '/pull/(\d+)') { [int]$Matches[1] } else { 0 }
                            Add-ReviewItem -State $State -IssueNumber $issueNum -PrUrl $prUrl -PrNumber $prNumber
                        } else {
                            Write-Host "[MONITOR]   -> Aufgabe abgeschlossen ohne PR (keine Codeaenderungen)." -ForegroundColor Yellow
                        }
                        Complete-Delegation -State $State -IssueNumber $issueNum -Result "completed"
                    } elseif ($currentState -eq "FAILED") {
                        Write-Host "[MONITOR]   -> FAILED! Local Agent fehlgeschlagen." -ForegroundColor Red
                        Add-ErrorLog -State $State -Message "Local agent $agentType failed for #$issueNum" -Context "Check terminal logs"
                        if (-not $DryRun.IsPresent) {
                            Set-DelegationEscalation -State $State -IssueNumber $issueNum -Reason "FAILED"
                        } else {
                            Complete-Delegation -State $State -IssueNumber $issueNum -Result "failed"
                        }
                    }
                } catch {
                    Write-Warning "[MONITOR]   #{0} Lokaler Status-File Fehler: $_"
                }
            } else {
                Write-Host ("[MONITOR]   #{0} (Local Agent: {1}): INITIALIZING..." -f $issueNum, $agentType) -ForegroundColor DarkGray
            }
        }
    }

    # --- Step 2b: Fill free Jules slots from safe queued issues ---
    Start-JulesRefill -State $State -Config $Config -QuotaRegistry $QuotaRegistry -Repository $repo -VarDbDir $VarDbDir -DryRun:$DryRun

    # --- Step 3: Process review queue ---
    $pendingReviews = @($State.review_queue | Where-Object {
        (Test-ObjectProperty -Object $_ -Name "review_status") -and [string]$_.review_status -eq "pending"
    })
    if ($pendingReviews.Count -gt 0) {
        Write-Host "[MONITOR] $($pendingReviews.Count) PRs in der Claude-Code Review-Queue." -ForegroundColor Cyan

        foreach ($review in $pendingReviews) {
            try {
                $prNum = [int]$review.pr_number
                $prObj = $prs | Where-Object { [int]$_.number -eq $prNum } | Select-Object -First 1
                if ($null -eq $prObj) {
                    $review | Add-Member -MemberType NoteProperty -Name "review_status" -Value "skipped" -Force
                    $review | Add-Member -MemberType NoteProperty -Name "summary" -Value "PR ist nicht mehr offen." -Force
                    continue
                }

                $reviewType = Get-CeoPrReviewType -QuotaRegistry $QuotaRegistry -Config $Config -State $State -PullRequest $prObj -DryRun:$DryRun
                $review | Add-Member -MemberType NoteProperty -Name "review_type" -Value $reviewType -Force
                $review | Add-Member -MemberType NoteProperty -Name "review_status" -Value "in_progress" -Force
                $review | Add-Member -MemberType NoteProperty -Name "started_at" -Value (Get-Date -Format 'o') -Force
                Save-AutopilotState -State $State
                Add-ReviewSessionRecord -State $State -ReviewItem $review -Status "in_progress" -ReviewType $reviewType

                $reviewResult = Invoke-ClaudePrReviewSession -QuotaRegistry $QuotaRegistry -Repository $repo -ReviewItem $review -ReviewType $reviewType -DryRun:$DryRun
                if (-not $reviewResult.success) {
                    $review | Add-Member -MemberType NoteProperty -Name "review_status" -Value "failed" -Force
                    $review | Add-Member -MemberType NoteProperty -Name "error" -Value $reviewResult.error -Force
                    $review | Add-Member -MemberType NoteProperty -Name "summary" -Value "Claude Code Review fehlgeschlagen: $($reviewResult.error)" -Force
                    Add-ReviewSessionRecord -State $State -ReviewItem $review -Status "failed" -ReviewType $reviewType -Error $review.summary
                    Add-ErrorLog -State $State -Message "Claude Code review failed for PR #$prNum" -Context ([string]$reviewResult.output)
                    Write-Host "[MONITOR]   Claude-Code Review fuer PR #$prNum fehlgeschlagen." -ForegroundColor Red
                    continue
                }

                $decision = ConvertTo-PrReviewDecision -RawOutput ([string]$reviewResult.output)
                $review | Add-Member -MemberType NoteProperty -Name "decision" -Value $decision.decision -Force
                $review | Add-Member -MemberType NoteProperty -Name "summary" -Value $decision.summary -Force
                $review | Add-Member -MemberType NoteProperty -Name "completed_at" -Value (Get-Date -Format 'o') -Force
                if ($decision.decision -eq "APPROVE") {
                    Set-GitHubPrReviewDecision -Repository $repo -PullRequestNumber $prNum -Decision "APPROVE" -Body $decision.summary -DryRun:$DryRun
                    $review | Add-Member -MemberType NoteProperty -Name "review_status" -Value "approved" -Force
                    Write-Host "[MONITOR]   PR #$prNum durch Claude Code freigegeben ($reviewType)." -ForegroundColor Green
                } else {
                    Set-GitHubPrReviewDecision -Repository $repo -PullRequestNumber $prNum -Decision "REQUEST_CHANGES" -Body $decision.summary -DryRun:$DryRun
                    $review | Add-Member -MemberType NoteProperty -Name "review_status" -Value "changes_requested" -Force
                    Write-Host "[MONITOR]   PR #$prNum braucht Aenderungen laut Claude Code ($reviewType)." -ForegroundColor Yellow
                }
                Add-ReviewSessionRecord -State $State -ReviewItem $review -Status $review.review_status -ReviewType $reviewType -Decision $decision.decision -Summary $decision.summary
                Save-AutopilotState -State $State
            } catch {
                $review | Add-Member -MemberType NoteProperty -Name "review_status" -Value "failed" -Force
                $review | Add-Member -MemberType NoteProperty -Name "error" -Value $_.Exception.Message -Force
                $catchReviewType = if (Test-ObjectProperty -Object $review -Name "review_type") { [string]$review.review_type } else { "" }
                Add-ReviewSessionRecord -State $State -ReviewItem $review -Status "failed" -ReviewType $catchReviewType -Error $_.Exception.Message
                Add-ErrorLog -State $State -Message "Review processing failed for PR #$($review.pr_number)" -Context $_.Exception.Message
                Write-Warning "[MONITOR] Review-Verarbeitung fuer PR #$($review.pr_number) fehlgeschlagen: $_"
            }
        }
    }

    # --- Step 4: Cleanup decisions_pending ---
    Write-Host "[MONITOR] Bereinige und dedupliziere offene Entscheidungen..." -ForegroundColor Cyan
    $cleanedDecisions = @()
    $seenTopics = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($decision in $State.decisions_pending) {
        $topic = $decision.topic

        # 1. Duplikatprüfung
        if ($seenTopics.Contains($topic)) {
            Write-Host "[MONITOR] Duplikat von Entscheidung entfernt: $topic" -ForegroundColor DarkGray
            continue
        }

        $keep = $true

        # 2. PR-Konflikt-Meldungen analysieren
        if ($topic -match 'PR #(\d+) hat Merge-Konflikte') {
            $prNum = [int]$Matches[1]
            $matchingPr = $prs | Where-Object { [int]$_.number -eq $prNum }
            if ($null -eq $matchingPr) {
                Write-Host "[MONITOR] PR #$prNum ist nicht mehr offen. Entferne Merge-Konflikt-Entscheidung." -ForegroundColor Green
                $keep = $false
            } elseif ($matchingPr.mergeable -ne "CONFLICTING") {
                Write-Host "[MONITOR] PR #$prNum hat keine Konflikte mehr (Status: $($matchingPr.mergeable)). Entferne Entscheidung." -ForegroundColor Green
                $keep = $false
            }
        }
        # 3. Jules-Session-Hilferufe analysieren
        elseif ($topic -match 'Jules Session #(\d+) braucht Hilfe') {
            $issueNum = [int]$Matches[1]
            $delegation = $State.active_delegations | Where-Object { [int]$_.issue_number -eq $issueNum }
            if ($null -eq $delegation) {
                Write-Host "[MONITOR] Delegation fuer Issue #$issueNum existiert nicht mehr. Entferne Entscheidung." -ForegroundColor Green
                $keep = $false
            } elseif ($delegation.jules_state -ne "AWAITING_USER_FEEDBACK") {
                Write-Host "[MONITOR] Jules Session fuer Issue #$issueNum wartet nicht mehr auf Feedback (Status: $($delegation.jules_state)). Entferne Entscheidung." -ForegroundColor Green
                $keep = $false
            }
        }

        if ($keep) {
            $seenTopics.Add($topic) | Out-Null
            $cleanedDecisions += @($decision)
        }
    }

    $State.decisions_pending = $cleanedDecisions

    # --- Step 5: Quota Monitoring ---
    Write-Host "[MONITOR] Pruefe Quota/Budget Limits..." -ForegroundColor Cyan
    foreach ($name in ($QuotaRegistry.providers.PSObject.Properties.Name)) {
        $p = $QuotaRegistry.providers.$name
        if (-not $p.enabled) { continue }

        $hasLimit = $p.PSObject.Properties.Name -contains "daily_limit"
        if ($hasLimit -and $p.daily_limit -and $p.daily_limit -gt 0) {
            $calls = if ($p.usage_today.PSObject.Properties.Name -contains "calls") { [int]$p.usage_today.calls } else { 0 }
            $usagePct = ($calls / $p.daily_limit) * 100
            if ($usagePct -ge 85) {
                $topic = "Quota Warnung: $name bei $([Math]::Round($usagePct))%"
                Add-DecisionPending -State $State -Topic $topic -Context "Provider $name hat $calls von $($p.daily_limit) Calls verbraucht. Bitte pruefen ob Limiterhoehung noetig."
            }
        }
    }

    # --- Step 6: Intelligent Branch Cleanup ---
    Write-Host "[MONITOR] Pruefe auf aufraeumbare Branches..." -ForegroundColor Cyan
    try {
        if (-not $DryRun.IsPresent) {
            Invoke-GitFetchPrune
            $goneBranches = Get-GitGoneBranches
            foreach ($bName in $goneBranches) {
                if ($bName -ne "main" -and $bName -ne "master") {
                    Write-Host "[MONITOR]   Loesche lokalen Branch: $bName (Upstream gone)" -ForegroundColor DarkGray
                    Delete-GitBranch -BranchName $bName -Force
                }
            }
        }
    } catch {
        Write-Warning "[MONITOR] Fehler beim Branch-Cleanup: $_"
    }

    $monitoringEndedAt = Get-Date
    $openPrCount = @($prs).Count
    $conflictCount = @($conflictingPrs).Count
    $queueNow = @($State.working_queue).Count
    $delegationsNow = @($State.active_delegations).Count
    $decisionsNow = @($State.decisions_pending).Count
    $failedWork = @($State.working_sessions | Where-Object { [string]$_.status -eq "FAILED" }).Count
    $monitoringSummary = "Offene PRs: $openPrCount; Konflikte: $conflictCount; Working-Queue: $monitoringQueueBefore -> $queueNow; Delegierungen: $monitoringDelegationsBefore -> $delegationsNow; Alerts: $monitoringDecisionsBefore -> $decisionsNow; fehlgeschlagene Working Sessions: $failedWork."
    if (-not (Test-ObjectProperty -Object $State -Name "run_summaries") -or $null -eq $State.run_summaries) {
        $State | Add-Member -MemberType NoteProperty -Name "run_summaries" -Value ([pscustomobject]@{}) -Force
    }
    $State.run_summaries | Add-Member -MemberType NoteProperty -Name "monitoring" -Value ([pscustomobject]@{
        started_at = $monitoringStartedAt.ToString("o")
        completed_at = $monitoringEndedAt.ToString("o")
        duration_seconds = [int][Math]::Round(($monitoringEndedAt - $monitoringStartedAt).TotalSeconds)
        summary = $monitoringSummary
    }) -Force

    $State.last_monitoring_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[MONITOR] ========== Monitoring abgeschlossen ==========" -ForegroundColor Blue
}
