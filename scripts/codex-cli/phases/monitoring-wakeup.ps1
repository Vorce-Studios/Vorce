# scripts/codex-cli/phases/monitoring-wakeup.ps1
# Monitoring Mode: Check running Jules sessions, PRs, merge conflicts

Set-StrictMode -Version Latest

# Test-ObjectProperty is now centrally defined in lib/state-manager.ps1

function Start-QueuedWorkingSessions {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Repository,
        [switch]$DryRun
    )

    Confirm-WorkingSessionsState -State $State
    $workingCfg = if (Test-ObjectProperty -Object $Config -Name "working_sessions") { $Config.working_sessions } else { $null }
    if ($workingCfg -and (Test-ObjectProperty -Object $workingCfg -Name "enabled") -and -not $workingCfg.enabled) {
        return
    }

    $maxConcurrent = if ($workingCfg -and (Test-ObjectProperty -Object $workingCfg -Name "max_concurrent")) { [int]$workingCfg.max_concurrent } else { 3 }
    if ($maxConcurrent -le 0) { return }

    $running = @($State.working_sessions | Where-Object { [string]$_.status -eq "IN_PROGRESS" }).Count
    $slots = $maxConcurrent - $running
    if ($slots -le 0 -or @($State.working_queue).Count -eq 0) { return }

    $scriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $toolsDir = Join-Path $scriptDir "tools"
    $quotaRegistryPath = Join-Path $scriptDir "quota-registry.json"

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

    $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $JulesScriptDir = Join-Path (Split-Path -Parent $ScriptDir) "jules"

    # Load Jules API functions
    $julesApiPath = Join-Path $JulesScriptDir "jules-api.ps1"
    if (Test-Path $julesApiPath) {
        . $julesApiPath
    }

    # --- Step 1: Fetch Open PRs ---
    Write-Host "[MONITOR] Pruefe offene PRs..." -ForegroundColor Cyan
    $prs = @()
    $conflictingPrs = @()

    # Use cached PR data from the dashboard instead of calling GitHub directly
    $cachedPrPath = Join-Path $ScriptDir "dashboard\public\pull-requests.json"
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
            $prOutput = gh pr list --repo $repo --state open --json number,title,headRefName,statusCheckRollup,mergeable,labels --limit 100 2>&1
            if ($LASTEXITCODE -eq 0) {
                $prs = @($prOutput | Out-String | ConvertFrom-Json | ForEach-Object { $_ })
            }
        }

        # --- Step 1.2: Run Monitoring Sequence (Session Splitting) ---
        if ($Config.PSObject.Properties.Name -contains "monitoring_sequence") {
            Write-Host "[MONITOR] Starte sequentielle Monitoring-Sequenz..." -ForegroundColor Yellow
            $monitoringContext = ""
            $prsData = $prs | ConvertTo-Json -Depth 3
            $sessionsData = $State.active_delegations | ConvertTo-Json -Depth 3

            $LagebildText = ""
            try {
                $LagebildText = Get-VorceLagebildSummary -State $State -Config $Config -QuotaRegistry $QuotaRegistry
            } catch {
                Write-Warning "[MONITOR] Konnte Lagebild-Zusammenfassung nicht generieren: $_"
            }

            foreach ($step in $Config.monitoring_sequence) {
                Write-Host "[MONITOR] Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan

                $promptVars = @{ repo = $repo }
                if ($step.id -eq "session_health" -or $step.prompt_ref -eq "monitor_sessions") {
                    $promptVars.sessions = $sessionsData
                } elseif ($step.id -eq "pr_ci_validation" -or $step.prompt_ref -eq "monitor_prs" -or $step.id -eq "conflict_remediation" -or $step.prompt_ref -eq "monitor_conflicts") {
                    $promptVars.prs = $prsData
                } elseif ($step.id -eq "monitoring_synthesis" -or $step.prompt_ref -eq "monitoring_synthesis") {
                    $promptVars.context = $monitoringContext
                } else {
                    $promptVars.prs = $prsData
                    $promptVars.sessions = $sessionsData
                    $promptVars.context = $monitoringContext
                }

                $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars

                $fullPrompt = ""
                if ($step.id -eq "monitoring_synthesis" -or $step.prompt_ref -eq "monitoring_synthesis") {
                    $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$LagebildText`n`n$stepPrompt"
                } else {
                    $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"
                }

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
        }

        # PR-Konflikte werden in der Planning-Phase gebuendelt und an Working Sessions delegiert.
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

        $agentType = if ($delegation.PSObject.Properties.Name -contains "agent_type" -and $delegation.agent_type) { $delegation.agent_type } else { "jules" }

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
                $session = Get-JulesSession -SessionIdOrName $sessionId -ApiKey $env:JULES_API_KEY
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

                            # In Ausnahmefällen, wenn Jules es nicht selbst schafft, eskalieren wir, damit das im Planning-Modus/CEO-Check analysiert wird.
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
            # Check local CLI agent status file
            $scriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
            $statusFile = Join-Path $scriptDir "tmp\agent-tasks\$issueNum.json"
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
                            $workSession.last_checked_at = (Get-Date -Format 'o')
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

    # --- Step 3: Process review queue ---
    $pendingReviews = @($State.review_queue | Where-Object { $_.review_status -eq "pending" })
    if ($pendingReviews.Count -gt 0) {
        Write-Host "[MONITOR] $($pendingReviews.Count) PRs im Review-Queue." -ForegroundColor Cyan

        foreach ($review in $pendingReviews) {
            $reviewResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "code_review" -DryRun:$DryRun -State $State -Prompt @"
Review PR #$($review.pr_number) fuer Issue #$($review.issue_number) im Repository $repo.
PR URL: $($review.pr_url)

1. Pruefe den Code auf Qualitaet, Rust-Konventionen und moegliche Regressionen.
2. Poste deine Ergebnisse als Kommentar auf dem PR.
3. Antworte mit PASS oder REJECT und einer kurzen Begruendung.
"@

            if ($reviewResult.success) {
                $review.review_status = "completed"
                Write-Host "[MONITOR]   Review fuer PR #$($review.pr_number) abgeschlossen via $($reviewResult.provider)." -ForegroundColor Green
            } else {
                Write-Host "[MONITOR]   Review fuer PR #$($review.pr_number) fehlgeschlagen." -ForegroundColor Red
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
                # PR ist nicht mehr offen
                Write-Host "[MONITOR] PR #$prNum ist nicht mehr offen. Entferne Merge-Konflikt-Entscheidung." -ForegroundColor Green
                $keep = $false
            } elseif ($matchingPr.mergeable -ne "CONFLICTING") {
                # PR hat keine Konflikte mehr
                Write-Host "[MONITOR] PR #$prNum hat keine Konflikte mehr (Status: $($matchingPr.mergeable)). Entferne Entscheidung." -ForegroundColor Green
                $keep = $false
            }
        }
        # 3. Jules-Session-Hilferufe analysieren
        elseif ($topic -match 'Jules Session #(\d+) braucht Hilfe') {
            $issueNum = [int]$Matches[1]
            $delegation = $State.active_delegations | Where-Object { [int]$_.issue_number -eq $issueNum }
            if ($null -eq $delegation) {
                # Delegation existiert nicht mehr
                Write-Host "[MONITOR] Delegation fuer Issue #$issueNum existiert nicht mehr. Entferne Entscheidung." -ForegroundColor Green
                $keep = $false
            } elseif ($delegation.jules_state -ne "AWAITING_USER_FEEDBACK") {
                # Session wartet nicht mehr auf Feedback
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
            $null = git fetch --prune 2>&1
            $goneBranches = git branch -vv | Select-String -Pattern "\[.*: gone\]"
            if ($null -ne $goneBranches) {
                foreach ($b in $goneBranches) {
                    $bName = ($b.Line.Trim() -split '\s+')[0]
                    if ($bName -eq "*") { $bName = ($b.Line.Trim() -split '\s+')[1] }
                    if ($bName -ne "main" -and $bName -ne "master") {
                        Write-Host "[MONITOR]   Loesche lokalen Branch: $bName (Upstream gone)" -ForegroundColor DarkGray
                        git branch -D $bName 2>&1 | Out-Null
                    }
                }
            }
        }
    } catch {
        Write-Warning "[MONITOR] Fehler beim Branch-Cleanup: $_"
    }

    $State.last_monitoring_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[MONITOR] ========== Monitoring abgeschlossen ==========" -ForegroundColor Blue
}
