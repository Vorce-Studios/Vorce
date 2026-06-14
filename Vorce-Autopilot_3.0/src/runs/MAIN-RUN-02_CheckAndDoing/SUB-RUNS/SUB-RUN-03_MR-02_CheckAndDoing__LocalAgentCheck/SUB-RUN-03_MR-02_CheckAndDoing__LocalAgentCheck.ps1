# src/runs/SUB-RUN/SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck.ps1
# Prueft alle aktiven lokalen Agent-Delegierungen (gemini_cli, claude_code, etc.)
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-03 LocalAgentCheck: Pruefe lokale Agent-Sessions..." -ForegroundColor Cyan

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"

$localDelegations = @($GlobalState.active_delegations | Where-Object {
    $agentType = if ($_.PSObject.Properties.Name -contains "agent_type" -and $_.agent_type) { [string]$_.agent_type } else { "jules" }
    $sessionId = [string]$_.jules_session_id
    ($agentType -ne "jules") -or ($sessionId -match "^local-agent-")
})

Write-Host "[CHECK&DOING] $($localDelegations.Count) aktive lokale Agent-Delegierungen gefunden." -ForegroundColor DarkGray

foreach ($delegation in $localDelegations) {
    $issueNum = [int]$delegation.issue_number
    $sessionId = [string]$delegation.jules_session_id
    $agentType = if ($delegation.PSObject.Properties.Name -contains "agent_type" -and $delegation.agent_type) { [string]$delegation.agent_type } else { "local_agent" }

    if ($sessionId -match "^dry-run") {
        Write-Host ("[CHECK&DOING]   #{0} [DRY RUN] Ueberspringe." -f $issueNum) -ForegroundColor DarkGray
        continue
    }

    # --- Stalled-Session-Detection (45 min Timeout) ---
    $delegatedAtStr = $delegation.delegated_at
    if (-not [string]::IsNullOrWhiteSpace($delegatedAtStr)) {
        try {
            $delegatedAt = [datetimeoffset]::Parse($delegatedAtStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $timeSinceDelegation = (Get-Date) - $delegatedAt.LocalDateTime
            if ($timeSinceDelegation.TotalMinutes -ge 45) {
                Write-Host ("[CHECK&DOING]   #{0} (Agent: {1}): Stalled-Session erkannt ({2:N0} min)! Eskaliere sofort." -f $issueNum, $agentType, $timeSinceDelegation.TotalMinutes) -ForegroundColor Red
                Add-ErrorLog -State $GlobalState -Message "Stalled session detected for #$issueNum (>45min)" -Context "Session: $sessionId, Agent: $agentType"
                if (-not $DryRun.IsPresent) {
                    Set-DelegationEscalation -State $GlobalState -IssueNumber $issueNum -Reason "STALLED_TIMEOUT" -FailureDetails "Session $sessionId reagiert seit mindestens 45 Minuten nicht." -NextRetryAt (Get-NextCheckDoingRetryAt -Config $Config)
                } else {
                    Complete-Delegation -State $GlobalState -IssueNumber $issueNum -Result "failed_timeout"
                }
                continue
            }
        } catch {
            Write-Warning "[CHECK&DOING] Could not parse delegated_at: $delegatedAtStr"
        }
    }

    $statusFile = Join-Path $VarDbDir "agent-tasks/$issueNum.json"
    if (Test-Path $statusFile) {
        try {
            $agentState = Get-Content $statusFile -Raw | ConvertFrom-Json
            $currentState = $agentState.status

            Write-Host ("[CHECK&DOING]   #{0} (Local Agent: {1}): {2}" -f $issueNum, $agentType, $currentState) -ForegroundColor $(
                switch ($currentState) {
                    "COMPLETED"   { "Green" }
                    "IN_PROGRESS" { "Cyan" }
                    "FAILED"      { "Red" }
                    default       { "Yellow" }
                }
            )

            Update-DelegationState -State $GlobalState -IssueNumber $issueNum -JulesState $currentState

            # Update working_sessions
            foreach ($workSession in $GlobalState.working_sessions) {
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
                    Write-Host "[CHECK&DOING]   -> Local PR gefunden: $prUrl" -ForegroundColor Green
                    Update-DelegationState -State $GlobalState -IssueNumber $issueNum -JulesState $currentState -PrUrl $prUrl
                    $prNumber = if ($prUrl -match '/pull/(\d+)') { [int]$Matches[1] } else { 0 }
                    Add-ReviewItem -State $GlobalState -IssueNumber $issueNum -PrUrl $prUrl -PrNumber $prNumber
                } else {
                    Write-Host "[CHECK&DOING]   -> Aufgabe abgeschlossen ohne PR (keine Codeaenderungen)." -ForegroundColor Yellow
                }
                Complete-Delegation -State $GlobalState -IssueNumber $issueNum -Result "completed"
            } elseif ($currentState -eq "FAILED") {
                $failureDetails = if ((Test-ObjectProperty -Object $agentState -Name "error") -and -not [string]::IsNullOrWhiteSpace([string]$agentState.error)) {
                    [string]$agentState.error
                } else {
                    "Provider meldete FAILED, hat aber keine Fehlerdetails geschrieben."
                }
                $nextRetryAt = Get-NextCheckDoingRetryAt -Config $Config
                foreach ($workSession in $GlobalState.working_sessions) {
                    if ([int]$workSession.issue_number -eq $issueNum) {
                        $workSession | Add-Member -MemberType NoteProperty -Name "failure_reason" -Value $failureDetails -Force
                        $workSession | Add-Member -MemberType NoteProperty -Name "retry_status" -Value "QUEUED_FOR_RETRY" -Force
                        $workSession | Add-Member -MemberType NoteProperty -Name "next_retry_at" -Value $nextRetryAt -Force
                        break
                    }
                }
                Write-Host "[CHECK&DOING]   -> FAILED! Local Agent fehlgeschlagen." -ForegroundColor Red
                Write-Host "[CHECK&DOING]      Ursache: $failureDetails" -ForegroundColor Red
                Write-Host "[CHECK&DOING]      Naechster Retry via Planning: $nextRetryAt" -ForegroundColor Yellow
                Add-ErrorLog -State $GlobalState -Message "Local agent $agentType failed for #$issueNum" -Context $failureDetails
                if (-not $DryRun.IsPresent) {
                    Set-DelegationEscalation -State $GlobalState -IssueNumber $issueNum -Reason "FAILED" -FailureDetails $failureDetails -NextRetryAt $nextRetryAt
                } else {
                    Complete-Delegation -State $GlobalState -IssueNumber $issueNum -Result "failed"
                }
            }
        } catch {
            Write-Warning "[CHECK&DOING]   #$issueNum Lokaler Status-File Fehler: $_"
        }
    } else {
        Write-Host ("[CHECK&DOING]   #{0} (Local Agent: {1}): INITIALIZING..." -f $issueNum, $agentType) -ForegroundColor DarkGray
    }
}

$SubState.status = "completed"
