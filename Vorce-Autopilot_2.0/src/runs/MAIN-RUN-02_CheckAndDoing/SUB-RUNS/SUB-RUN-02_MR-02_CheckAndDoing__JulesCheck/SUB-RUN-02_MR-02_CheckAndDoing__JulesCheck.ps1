# src/runs/SUB-RUN/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck.ps1
# Prueft alle aktiven Jules-Delegierungen: Timeout, Auto-Approve, Retry, Eskalation
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-02 JulesCheck: Pruefe aktive Jules-Sessions..." -ForegroundColor Cyan

$repo = $Config.repository
$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"

# Lade PRs fuer Matching
$prs = @()
$cachedPrPath = Join-Path $VarDbDir "pull-requests.json"
if (Test-Path $cachedPrPath) {
    try {
        $prsRaw = Get-Content -LiteralPath $cachedPrPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $prsRaw -and ($prsRaw -is [System.Array] -or $prsRaw -is [System.Collections.IList])) {
            $prs = @($prsRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo })
        }
    } catch {}
}
if ($prs.Count -eq 0) {
    try { $prs = Get-GitHubPullRequests -Repository $repo -Limit 100 } catch { $prs = @() }
}

# Speichere PRs im MainState fuer spaetere SUB-RUNs
if (-not ($MainState.PSObject.Properties.Name -contains "OpenPRs")) {
    $MainState | Add-Member -MemberType NoteProperty -Name "OpenPRs" -Value @() -Force
}
$MainState.OpenPRs = $prs

$julesDelegations = @($GlobalState.active_delegations | Where-Object {
    $agentType = if ($_.PSObject.Properties.Name -contains "agent_type" -and $_.agent_type) { [string]$_.agent_type } else { "jules" }
    $sessionId = [string]$_.jules_session_id
    $agentType -eq "jules" -and -not ($sessionId -match "^local-agent-") -and -not ($sessionId -match "^dry-run")
})

Write-Host "[CHECK&DOING] $($julesDelegations.Count) aktive Jules-Delegierungen gefunden." -ForegroundColor DarkGray

foreach ($delegation in $julesDelegations) {
    $issueNum = [int]$delegation.issue_number
    $sessionId = [string]$delegation.jules_session_id

    # --- Stalled-Session-Detection (45 min Timeout) ---
    $delegatedAtStr = $delegation.delegated_at
    if (-not [string]::IsNullOrWhiteSpace($delegatedAtStr)) {
        try {
            $delegatedAt = [datetimeoffset]::Parse($delegatedAtStr, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $timeSinceDelegation = (Get-Date) - $delegatedAt.LocalDateTime
            if ($timeSinceDelegation.TotalMinutes -ge 45) {
                Write-Host ("[CHECK&DOING]   #{0}: Stalled-Session erkannt ({1:N0} min)! Eskaliere sofort." -f $issueNum, $timeSinceDelegation.TotalMinutes) -ForegroundColor Red
                Add-ErrorLog -State $GlobalState -Message "Stalled session detected for #$issueNum (>45min)" -Context "Session: $sessionId"

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

    try {
        $session = Get-JulesSessionStatus -SessionId $sessionId -ApiKey $env:JULES_API_KEY
        if ($null -eq $session) {
            throw "Session $sessionId konnte nicht geladen werden."
        }
        $julesState = [string]$session.state

        Write-Host ("[CHECK&DOING]   #{0} ({1}): {2}" -f $issueNum, $sessionId, $julesState) -ForegroundColor $(
            switch ($julesState) {
                "COMPLETED"  { "Green" }
                "IN_PROGRESS" { "Cyan" }
                "QUEUED"     { "DarkGray" }
                "PLANNING"   { "Cyan" }
                default      { "Yellow" }
            }
        )

        Update-DelegationState -State $GlobalState -IssueNumber $issueNum -JulesState $julesState

        switch ($julesState) {
            "COMPLETED" {
                $prUrl = Get-JulesSessionPullRequestUrl -Session $session
                if (-not [string]::IsNullOrWhiteSpace($prUrl)) {
                    Write-Host "[CHECK&DOING]   -> PR gefunden: $prUrl" -ForegroundColor Green
                    Update-DelegationState -State $GlobalState -IssueNumber $issueNum -JulesState $julesState -PrUrl $prUrl
                    $prNumber = if ($prUrl -match '/pull/(\d+)') { [int]$Matches[1] } else { 0 }
                    Add-ReviewItem -State $GlobalState -IssueNumber $issueNum -PrUrl $prUrl -PrNumber $prNumber
                }
                Complete-Delegation -State $GlobalState -IssueNumber $issueNum -Result "completed"
            }
            "AWAITING_PLAN_APPROVAL" {
                if ($Config.jules.auto_approve_plans) {
                    Write-Host "[CHECK&DOING]   -> Auto-Approve Plan" -ForegroundColor Yellow
                    if (-not $DryRun.IsPresent) {
                        Approve-JulesPlan -SessionIdOrName $sessionId -ApiKey $env:JULES_API_KEY
                    }
                }
            }
            "AWAITING_USER_FEEDBACK" {
                $retryCount = [int]$delegation.retry_count
                $maxRetries = [int]$Config.jules.auto_retry_feedback_max

                if ($retryCount -lt $maxRetries) {
                    $retryMsg = "[CHECK&DOING]   -> Auto-Retry ({0}/{1})" -f ($retryCount + 1), $maxRetries
                    Write-Host $retryMsg -ForegroundColor Yellow
                    if (-not $DryRun.IsPresent) {
                        Send-JulesMessage -SessionIdOrName $sessionId -Message "Continue with the task. If blocked, skip the problematic step and proceed." -ApiKey $env:JULES_API_KEY
                    }
                    $delegation.retry_count = $retryCount + 1
                } else {
                    Write-Host "[CHECK&DOING]   -> ESKALATION: Re-Planning / Fehlerbehebung erforderlich!" -ForegroundColor Red
                    if (-not $DryRun.IsPresent) {
                        Set-DelegationEscalation -State $GlobalState -IssueNumber $issueNum -Reason "FEEDBACK_TIMEOUT_CI_OR_BLOCKER" -FailureDetails "Jules wartet nach $retryCount automatischen Fortsetzungsversuchen weiterhin auf Feedback." -NextRetryAt (Get-NextCheckDoingRetryAt -Config $Config)
                    }
                }
            }
            "FAILED" {
                Write-Host "[CHECK&DOING]   -> FAILED! Logge Fehler und eskaliere." -ForegroundColor Red
                Add-ErrorLog -State $GlobalState -Message "Jules session failed for #$issueNum" -Context "Session: $sessionId"
                if (-not $DryRun.IsPresent) {
                    Set-DelegationEscalation -State $GlobalState -IssueNumber $issueNum -Reason "FAILED" -FailureDetails "Jules meldete den Session-Status FAILED fuer Session $sessionId." -NextRetryAt (Get-NextCheckDoingRetryAt -Config $Config)
                } else {
                    Complete-Delegation -State $GlobalState -IssueNumber $issueNum -Result "failed"
                }
            }
        }
    } catch {
        Write-Warning ("[CHECK&DOING]   #{0} API-Fehler: {1}" -f $issueNum, $_)
        Add-ErrorLog -State $GlobalState -Message "API error for #$issueNum" -Context $_.Exception.Message
    }
}

$SubState.status = "completed"
