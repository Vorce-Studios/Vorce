# src/runs/SUB-RUN/SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping.ps1
# Alert-Cleanup, Quota-Monitoring, Branch-Prune, Run-Summary
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-06 Housekeeping: Aufraeum- und Statusarbeiten..." -ForegroundColor Cyan


# Lade PRs aus MainState (falls bereits verfuegbar)
$prs = @()
if ($MainState.PSObject.Properties.Name -contains "OpenPRs" -and $null -ne $MainState.OpenPRs) {
    $prs = @($MainState.OpenPRs)
}

# --- Step 1: Cleanup decisions_pending (mit Memory-Integration) ---
Write-Host "[CHECK&DOING] Bereinige und dedupliziere offene Entscheidungen..." -ForegroundColor Cyan
$cleanedDecisions = @()
$seenTopics = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($decision in $GlobalState.decisions_pending) {
    $topic = $decision.topic
    $id = if ($decision.PSObject.Properties.Name -contains "id") { $decision.id } else { "" }

    # Skip closed/ignored alerts
    if ($decision.PSObject.Properties.Name -contains "status") {
        if ($decision.status -eq 'closed' -or $decision.status -eq 'ignored') {
            # Convert to memory if usercomment exists and memory NOT yet created
            if (-not $decision.PSObject.Properties.Name -contains "memory_id" -and
                $decision.PSObject.Properties.Name -contains "user_comment" -and
                -not [string]::IsNullOrWhiteSpace($decision.user_comment)) {

                try {
                    $memResult = Add-Memory `
                        -Text "IGNORE_ALERT: $topic`nDetails: $($decision.context)`nUser-Kommentar: $($decision.user_comment)" `
                        -Type "temporary" `
                        -Priority "medium" `
                        -Source "audit_alert_close"

                    if ($memResult) {
                        $decision | Add-Member -MemberType NoteProperty -Name "memory_id" -Value "mem-auto-$id" -Force
                        Write-Host "[CHECK&DOING] Memory erstellt fuer geschlossenen Alert: $topic" -ForegroundColor Cyan
                    }
                } catch {
                    Write-Warning "[CHECK&DOING] Konnte Memory fuer Alert nicht erstellen: $_"
                }
            }

            $closedAtStr = if ($decision.PSObject.Properties.Name -contains "closed_at") { $decision.closed_at } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($closedAtStr)) {
                try {
                    $closedAt = [datetime]$closedAtStr
                    if ((Get-Date) - $closedAt -gt [timespan]::FromDays(3)) {
                        Write-Host "[CHECK&DOING] Entscheidung geschlossen/ignoriert (>3 Tage alt), entferne aus decisions_pending: $topic" -ForegroundColor DarkGray
                        continue
                    }
                } catch {}
            }
        }
    }

    # Duplikatpruefung (nur fuer pending alerts)
    if ($seenTopics.Contains($topic)) {
        Write-Host "[CHECK&DOING] Duplikat von Entscheidung entfernt: $topic" -ForegroundColor DarkGray
        continue
    }

    $keep = $true

    # PR-Konflikt-Meldungen analysieren
    if ($topic -match 'PR #(\\d+) hat Merge-Konflikte') {
        $prNum = [int]$Matches[1]
        $matchingPr = $prs | Where-Object { [int]$_.number -eq $prNum }
        if ($null -eq $matchingPr) {
            Write-Host "[CHECK&DOING] PR #$prNum ist nicht mehr offen. Entferne Merge-Konflikt-Entscheidung." -ForegroundColor Green
            $keep = $false
        } elseif ($matchingPr.mergeable -ne "CONFLICTING") {
            Write-Host "[CHECK&DOING] PR #$prNum hat keine Konflikte mehr (Status: $($matchingPr.mergeable)). Entferne Entscheidung." -ForegroundColor Green
            $keep = $false
        }
    }
    # Jules-Session-Hilferufe analysieren
    elseif ($topic -match 'Jules Session #(\\d+) braucht Hilfe') {
        $issueNum = [int]$Matches[1]
        $delegation = $GlobalState.active_delegations | Where-Object { [int]$_.issue_number -eq $issueNum }
        if ($null -eq $delegation) {
            Write-Host "[CHECK&DOING] Delegation fuer Issue #$issueNum existiert nicht mehr. Entferne Entscheidung." -ForegroundColor Green
            $keep = $false
        } elseif ($delegation.jules_state -ne "AWAITING_USER_FEEDBACK") {
            Write-Host "[CHECK&DOING] Jules Session fuer Issue #$issueNum wartet nicht mehr auf Feedback (Status: $($delegation.jules_state)). Entferne Entscheidung." -ForegroundColor Green
            $keep = $false
        }
    }

    if ($keep) {
        $seenTopics.Add($topic) | Out-Null
        $cleanedDecisions += @($decision)
    }
}

$GlobalState.decisions_pending = $cleanedDecisions

# --- Step 2: Quota Monitoring ---
Write-Host "[CHECK&DOING] Pruefe Quota/Budget Limits..." -ForegroundColor Cyan
foreach ($name in ($QuotaRegistry.providers.PSObject.Properties.Name)) {
    $p = $QuotaRegistry.providers.$name
    if (-not $p.enabled) { continue }

    $hasLimit = $p.PSObject.Properties.Name -contains "daily_limit"
    if ($hasLimit -and $p.daily_limit -and $p.daily_limit -gt 0) {
        $calls = if ($p.usage_today.PSObject.Properties.Name -contains "calls") { [int]$p.usage_today.calls } else { 0 }
        $usagePct = ($calls / $p.daily_limit) * 100
        if ($usagePct -ge 85) {
            $topic = "Quota Warnung: $name bei $([Math]::Round($usagePct))%"
            Add-DecisionPending -State $GlobalState -Topic $topic -Context "Provider $name hat $calls von $($p.daily_limit) Calls verbraucht. Bitte pruefen ob Limiterhoehung noetig."
        }
    }
}

# --- Step 3: Intelligent Branch Cleanup ---
Write-Host "[CHECK&DOING] Pruefe auf aufraeumbare Branches..." -ForegroundColor Cyan
try {
    if (-not $DryRun.IsPresent) {
        Invoke-GitFetchPrune
        $goneBranches = Get-GitGoneBranches
        foreach ($bName in $goneBranches) {
            if ($bName -ne "main" -and $bName -ne "master") {
                Write-Host "[CHECK&DOING]   Loesche lokalen Branch: $bName (Upstream gone)" -ForegroundColor DarkGray
                Delete-GitBranch -BranchName $bName -Force
            }
        }
    }
} catch {
    Write-Warning "[CHECK&DOING] Fehler beim Branch-Cleanup: $_"
}

# --- Step 4: Run-Summary ---
$conflictingPrs = @()
if ($MainState -is [hashtable] -and $MainState.ContainsKey("ConflictingPRs")) {
    $conflictingPrs = @($MainState["ConflictingPRs"])
} elseif ($MainState.PSObject.Properties.Name -contains "ConflictingPRs") {
    $conflictingPrs = @($MainState.ConflictingPRs)
}
$openPrCount = @($prs).Count
$conflictCount = @($conflictingPrs).Count
$queueNow = @($GlobalState.working_queue).Count
$delegationsNow = @($GlobalState.active_delegations).Count
$decisionsNow = @($GlobalState.decisions_pending).Count
$failedWork = @($GlobalState.working_sessions | Where-Object { [string]$_.status -eq "FAILED" }).Count
$checkDoingSummary = "Offene PRs: $openPrCount; Konflikte: $conflictCount; Working-Queue: $queueNow; Delegierungen: $delegationsNow; Alerts: $decisionsNow; fehlgeschlagene Working Sessions: $failedWork."

if (-not (Test-ObjectProperty -Object $GlobalState -Name "run_summaries") -or $null -eq $GlobalState.run_summaries) {
    $GlobalState | Add-Member -MemberType NoteProperty -Name "run_summaries" -Value ([pscustomobject]@{}) -Force
}
$GlobalState.run_summaries | Add-Member -MemberType NoteProperty -Name "check_and_doing" -Value ([pscustomobject]@{
    started_at = (Get-Date).ToString("o")
    completed_at = (Get-Date).ToString("o")
    summary = $checkDoingSummary
}) -Force

$GlobalState.last_check_and_doing_at = (Get-Date -Format 'o')
Save-AutopilotState -State $GlobalState

Write-Host "[CHECK&DOING] ========== Check&Doing abgeschlossen ==========" -ForegroundColor Blue

$SubState.status = "completed"
