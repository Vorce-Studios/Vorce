# scripts/codex-cli/phases/monitoring-wakeup.ps1
# Monitoring Mode: Check running Jules sessions, PRs, merge conflicts

Set-StrictMode -Version Latest

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
                        Write-Host "[MONITOR]   -> ESKALATION: Braucht manuellen Eingriff!" -ForegroundColor Red
                        $State.decisions_pending += @([ordered]@{
                            topic      = "Jules Session #$issueNum braucht Hilfe"
                            context    = "Session $sessionId ist nach $maxRetries Retries immer noch AWAITING_USER_FEEDBACK."
                            created_at = (Get-Date -Format 'o')
                        })
                    }
                }
                "FAILED" {
                    Write-Host "[MONITOR]   -> FAILED! Logge Fehler." -ForegroundColor Red
                    Add-ErrorLog -State $State -Message "Jules session failed for #$issueNum" -Context "Session: $sessionId"
                    Complete-Delegation -State $State -IssueNumber $issueNum -Result "failed"
                }
            }
        } catch {
            Write-Warning ("[MONITOR]   #{0} API-Fehler: {1}" -f $issueNum, $_)
            Add-ErrorLog -State $State -Message "API error for #$issueNum" -Context $_.Exception.Message
        }
    }

    # --- Step 2: Check open PRs for problems ---
    Write-Host "[MONITOR] Pruefe offene PRs auf Probleme..." -ForegroundColor Cyan

    try {
        $prsRaw = gh pr list --repo $repo --state open --json number,title,headRefName,statusCheckRollup,mergeable --limit 20 2>&1
        $prs = @($prsRaw | Out-String | ConvertFrom-Json | ForEach-Object { $_ })

        foreach ($pr in $prs) {
            $prNum = [int]$pr.number
            $mergeable = [string]$pr.mergeable

            # Check merge conflicts
            if ($mergeable -eq "CONFLICTING") {
                Write-Host ("[MONITOR]   PR #{0} MERGE CONFLICT!" -f $prNum) -ForegroundColor Red
                $State.decisions_pending += @([ordered]@{
                    topic      = "PR #$prNum hat Merge-Konflikte"
                    context    = "Branch: $($pr.headRefName) - Titel: $($pr.title)"
                    created_at = (Get-Date -Format 'o')
                })
            }

            # Check failing checks
            $failingChecks = @($pr.statusCheckRollup | Where-Object {
                $_.conclusion -eq "FAILURE" -or $_.status -eq "FAILURE"
            })

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

    $State.last_monitoring_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[MONITOR] ========== Monitoring abgeschlossen ==========" -ForegroundColor Blue
}
