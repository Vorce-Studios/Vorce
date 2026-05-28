# scripts/codex-cli/phases/monitoring-wakeup.ps1
# Monitoring Mode: Check running Jules sessions, PRs, merge conflicts

Set-StrictMode -Version Latest

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

    $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $JulesScriptDir = Join-Path (Split-Path -Parent $ScriptDir) "jules"

    # Load Jules API functions
    $julesApiPath = Join-Path $JulesScriptDir "jules-api.ps1"
    if (Test-Path $julesApiPath) {
        . $julesApiPath
    }

    # --- Step 1: Check active Jules sessions ---
    Write-Host "[MONITOR] Pruefe $($State.active_delegations.Count) aktive Delegierungen..." -ForegroundColor Cyan

    $toRemove = @()

    foreach ($delegation in $State.active_delegations) {
        $issueNum = [int]$delegation.issue_number
        $sessionId = [string]$delegation.jules_session_id

        if ($sessionId -eq "dry-run-$issueNum") {
            Write-Host ("[MONITOR]   #{0} [DRY RUN] Ueberspringe." -f $issueNum) -ForegroundColor DarkGray
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

            Update-DelegationState -State $State -IssueNumber $issueNum -JulesState $julesState

            switch ($julesState) {
                "COMPLETED" {
                    # Check for PR
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
                        Write-Host "[MONITOR]   -> ESKALATION: Re-Planning erforderlich!" -ForegroundColor Red
                        if (-not $DryRun.IsPresent) {
                            Escalate-Delegation -State $State -IssueNumber $issueNum -Reason "FEEDBACK_TIMEOUT"
                        }
                    }
                }
                "FAILED" {
                    Write-Host "[MONITOR]   -> FAILED! Logge Fehler und eskaliere." -ForegroundColor Red
                    Add-ErrorLog -State $State -Message "Jules session failed for #$issueNum" -Context "Session: $sessionId"
                    if (-not $DryRun.IsPresent) {
                        Escalate-Delegation -State $State -IssueNumber $issueNum -Reason "FAILED"
                    } else {
                        Complete-Delegation -State $State -IssueNumber $issueNum -Result "failed"
                    }
                }
            }
        } catch {
            Write-Warning ("[MONITOR]   #{0} API-Fehler: {1}" -f $issueNum, $_)
            Add-ErrorLog -State $State -Message "API error for #$issueNum" -Context $_.Exception.Message
        }
    }

    # --- Step 2: Check open PRs for problems ---
    Write-Host "[MONITOR] Pruefe offene PRs auf Probleme..." -ForegroundColor Cyan

    $prs = @()
    try {
        $prsRaw = gh pr list --repo $repo --state open --json number,title,headRefName,statusCheckRollup,mergeable --limit 100 2>&1
        $prs = @($prsRaw | Out-String | ConvertFrom-Json | ForEach-Object { $_ })

        foreach ($pr in $prs) {
            $prNum = [int]$pr.number
            $mergeable = [string]$pr.mergeable

            # Check merge conflicts
            if ($mergeable -eq "CONFLICTING") {
                Write-Host ("[MONITOR]   PR #{0} MERGE CONFLICT!" -f $prNum) -ForegroundColor Red
                Add-DecisionPending -State $State -Topic "PR #$prNum hat Merge-Konflikte" -Context "Branch: $($pr.headRefName) - Titel: $($pr.title)"
            }

            # Check failing checks
            $failingChecks = @()
            if ($pr.statusCheckRollup) {
                $failingChecks = @($pr.statusCheckRollup | Where-Object {
                    (Test-ObjectProperty -Object $_ -Name "conclusion" -and $_.conclusion -eq "FAILURE") -or
                    (Test-ObjectProperty -Object $_ -Name "status" -and $_.status -eq "FAILURE")
                })
            }


            if ($failingChecks.Count -gt 0) {
                $failNames = ($failingChecks | ForEach-Object { $_.name }) -join ", "
                Write-Host ("[MONITOR]   PR #{0} {1} Checks fehlgeschlagen ({2})" -f $prNum, $failingChecks.Count, $failNames) -ForegroundColor Red
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

    $State.last_monitoring_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[MONITOR] ========== Monitoring abgeschlossen ==========" -ForegroundColor Blue
}
