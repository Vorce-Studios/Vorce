# src/runs/SUB-RUN/SUB-RUN-04_MR-01_Planning__Delegation.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-04 Delegation: Erstelle und delegiere Issues..." -ForegroundColor Cyan

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"
$repo = $Config.repository

$candidates = if ($MainState.PSObject.Properties.Name -contains "PlanningCandidates") { $MainState.PlanningCandidates } else { @() }
$runIssueCreation = if ($MainState.PSObject.Properties.Name -contains "RunIssueCreation") { $MainState.RunIssueCreation } else { $false }
$newIssues = if ($MainState.PSObject.Properties.Name -contains "ProposedIssues") { $MainState.ProposedIssues } else { @() }

# --- Execute issue creation logic if issues were proposed ---
if ($runIssueCreation -and $newIssues.Count -gt 0) {
    try {
        $newIssuesCreated = $false

        # Use cached issue data from the dashboard instead of calling GitHub directly
        $cachedIssuePath = Join-Path $VarDbDir "github-issues.json"
        $existingVorceIssues = @()
        $issuesRaw = $null

        if (Test-Path $cachedIssuePath) {
            try {
                $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                Write-Warning "[PLANNING] Fehler beim Lesen der gecachten Issues: $_"
            }
        }

        if ($null -ne $issuesRaw -and ($issuesRaw -is [System.Array] -or $issuesRaw -is [System.Collections.IList])) {
            $existingVorceIssues = @($issuesRaw | Where-Object { $_.repo -eq $repo })
            Write-Host "[PLANNING] Gecachte Issue-Daten zur Vorce-ID-Ermittlung geladen." -ForegroundColor DarkGray
        } else {
            Write-Host "[PLANNING] Lade Issues direkt via gh-cli zur Vorce-ID-Ermittlung (Fallback)..." -ForegroundColor DarkGray
            $existingVorceIssues = Get-AllGitHubIssues -Repository $repo -Limit 1000
        }

        $nextIssueId = 1
        try {
            $nextIssueId = Get-NextVorceIssueId -Issues $existingVorceIssues
        } catch {
            Write-Warning "[PLANNING] Konnte naechste Vorce-Issue-ID nicht aus GitHub ermitteln; starte bei 001."
        }

        $seenTitles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($null -ne $existingVorceIssues) {
            foreach ($ei in $existingVorceIssues) {
                if (-not [string]::IsNullOrWhiteSpace($ei.title)) {
                    $seenTitles.Add([string]$ei.title) | Out-Null
                }
            }
        }

        foreach ($newIssue in $newIssues) {
            if ($null -eq $newIssue -or -not ($newIssue.PSObject.Properties.Name -contains "title")) { continue }
            $issueTitle = [string]$newIssue.title
            $issueBody = if ($newIssue.PSObject.Properties.Name -contains "body") { [string]$newIssue.body } else { "" }

            $issueType = if ($newIssue.PSObject.Properties.Name -contains "issue_type") { [string]$newIssue.issue_type } else { "default" }
            if (Test-VorceMasterIssueTitle -Title $issueTitle) { $issueType = "master" }
            if (Test-VorceSubIssueTitle -Title $issueTitle) { $issueType = "sub_issue" }
            if ($issueType -notin @("default", "master", "sub_issue")) { $issueType = "default" }

            if ($issueType -eq "sub_issue") {
                $parentMasterId = if ($newIssue.PSObject.Properties.Name -contains "parent_master_id") { [int]$newIssue.parent_master_id } else { Get-VorceIssueId -Title $issueTitle }
                $subIndex = if ($newIssue.PSObject.Properties.Name -contains "sub_index") { [int]$newIssue.sub_index } elseif ($issueTitle -match '^___M-\d{3}_s(\d+)_') { [int]$Matches[1] } else { 0 }
                try {
                    $issueTitle = Format-VorceIssueTitle -Type "sub_issue" -Title (ConvertTo-VorceTitleSlug -Title $issueTitle) -ParentMasterId $parentMasterId -SubIndex $subIndex
                } catch {
                    Write-Warning "[PLANNING] Ueberspringe ungueltigen Sub-Issue-Vorschlag '$issueTitle': $($_.Exception.Message)"
                    continue
                }
            } else {
                $issueTitle = Format-VorceIssueTitle -Type $issueType -Title (ConvertTo-VorceTitleSlug -Title $issueTitle) -Id $nextIssueId
                $nextIssueId++
            }

            if ($seenTitles.Contains($issueTitle)) {
                Write-Host "[PLANNING] Ueberspringe Erstellung: Issue mit Titel '$issueTitle' existiert bereits oder wurde gerade in dieser Iteration vorgeschlagen." -ForegroundColor Yellow
                continue
            }
            $seenTitles.Add($issueTitle) | Out-Null

            $issueAgent = "jules"
            if ($newIssue.PSObject.Properties.Name -contains "agent" -and -not [string]::IsNullOrWhiteSpace($newIssue.agent)) {
                $issueAgent = [string]$newIssue.agent
            }

            if ($issueAgent -eq "jules" -and -not (Test-AutopilotJulesIssueSafe -Title $issueTitle -Body $issueBody)) {
                Write-Host "[PLANNING] Jules fuer unsicheren/unklaren Issue-Vorschlag blockiert: '$issueTitle'. Route zu gemini_cli." -ForegroundColor Yellow
                $issueAgent = "gemini_cli"
            }

            if ($DryRun.IsPresent) {
                Write-Host "[PLANNING] [DRY RUN] Wuerde Issue erstellen: $issueTitle ($issueAgent)" -ForegroundColor DarkYellow
            } else {
                $labels = @(if ($newIssue.PSObject.Properties.Name -contains "labels") { $newIssue.labels } else { @() }) + @($Config.issue_filters.autopilot_label)
                if ($issueAgent -ne "jules") {
                    $labels = @($labels | Where-Object { $_ -ne "jules-task" })
                }
                $labels += "agent:$issueAgent"

                $created = New-GitHubIssue -Repository $repo -Title $issueTitle -Body $issueBody -Labels $labels
                Write-Host "[PLANNING] Issue erstellt: $created (Agent: $issueAgent)" -ForegroundColor Green
                $GlobalState.autopilot_created_issues += @($issueTitle)
                $newIssuesCreated = $true
            }
        }
        if ($newIssuesCreated) {
            Write-Host "[PLANNING] Neue Issues wurden erstellt. Die DataSync wird diese beim naechsten Durchlauf erfassen." -ForegroundColor Cyan
        }
    } catch {
        Write-Warning "[PLANNING] Fehler bei der Issue-Erstellung: $_"
    }
}

# --- Delegate to Jules or local CLI Agents ---
$julesProvider = $QuotaRegistry.providers.jules
$currentSessions = [int]$julesProvider.usage_today.calls
$maxDaily = [int]$Config.jules.max_daily_sessions
$maxConcurrent = [int]$Config.jules.max_concurrent_sessions
$activeDelegations = if ($null -ne $GlobalState -and $GlobalState.PSObject.Properties.Match("active_delegations").Count -gt 0 -and $null -ne $GlobalState.active_delegations) { @($GlobalState.active_delegations) } else { @() }
$julesActiveCount = @($activeDelegations | Where-Object {
    (-not ($_.PSObject.Properties.Name -contains "agent_type") -or ($_.agent_type -eq "jules")) -and
    (Test-PlanningJulesCapacityState -State $(if ($_.PSObject.Properties.Name -contains "jules_state") { [string]$_.jules_state } else { "QUEUED" }))
}).Count

$julesAvailableSlots = $maxConcurrent - $julesActiveCount
if (($maxDaily - $currentSessions) -lt $julesAvailableSlots) {
    $julesAvailableSlots = ($maxDaily - $currentSessions)
}
if ($julesAvailableSlots -lt 0) {
    $julesAvailableSlots = 0
}

$toPick = [Math]::Min($Config.max_issues_per_planning_cycle, $candidates.Count)

Write-Host "[PLANNING] Untersuche bis zu $toPick Issues. (Jules Slots: $julesAvailableSlots)" -ForegroundColor Cyan

$delegatedInThisRun = [System.Collections.Generic.HashSet[int]]::new()

for ($i = 0; $i -lt $toPick; $i++) {
    $issue = $candidates[$i]
    $issueNum = [int]$issue.number
    $issueTitle = [string]$issue.title

    if ($delegatedInThisRun.Contains($issueNum)) {
        Write-Host "[PLANNING] Ueberspringe Issue #$issueNum - Wurde bereits in diesem Lauf delegiert!" -ForegroundColor Yellow
        continue
    }

    $targetAgent = "jules"
    foreach ($label in $issue.labels) {
        $lname = if ($label -is [string]) { $label } else { $label.name }
        if ($lname -match "^agent:(.+)") {
            $targetAgent = $Matches[1]
            break
        }
    }

    $issueBody = if (($issue.PSObject.Properties.Name -contains "body") -and $null -ne $issue.body) { [string]$issue.body } else { "" }
    if ($targetAgent -eq "jules" -and -not (Test-AutopilotJulesIssueSafe -Title $issueTitle -Body $issueBody)) {
        Write-Host "[PLANNING] Jules blockiert fuer Issue #${issueNum}: kein sicherer konkreter Codeauftrag. Route zu gemini_cli." -ForegroundColor Yellow
        $targetAgent = "gemini_cli"
    }

    Write-Host ("[PLANNING] Delegiere Issue #{0}: {1} an Agent: {2}" -f $issueNum, $issueTitle, $targetAgent) -ForegroundColor Green

    if ($DryRun.IsPresent) {
        Write-Host "[PLANNING] [DRY RUN] Wuerde $targetAgent Session starten." -ForegroundColor DarkYellow
        if ($targetAgent -eq "jules") {
            Add-Delegation -State $GlobalState -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "dry-run-$issueNum" -AgentType $targetAgent -JobId "dry-run-job"
        } else {
            Add-WorkingQueueItem -State $GlobalState -IssueNumber $issueNum -IssueTitle $issueTitle -AgentProvider $targetAgent
            Save-AutopilotState -State $GlobalState
        }
        continue
    }

    if ($targetAgent -eq "jules") {
        if ($julesAvailableSlots -le 0) {
            Write-Host "[PLANNING] Jules-Kontingent erschoepft, ueberspringe Issue #$issueNum." -ForegroundColor Yellow
            continue
        }
        $julesAvailableSlots--

        try {
            $sessionId = New-JulesSession -IssueNumber $issueNum -Repository $repo -ApiKey $env:JULES_API_KEY -AutoCreatePr
            Add-Delegation -State $GlobalState -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId $sessionId -AgentType "jules"
            Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"

            if ($null -ne $GlobalState.escalated_issues) {
                $esc = $GlobalState.escalated_issues | Where-Object { [int]$_.issue_number -eq $issueNum }
                if ($esc) {
                    $esc.status = "RETRY_DISPATCHED"
                    Save-AutopilotState -State $GlobalState
                }
            }
        } catch {
            Write-Warning "[PLANNING] Jules Session fuer #$issueNum fehlgeschlagen: $_"
            Add-ErrorLog -State $GlobalState -Message "Jules delegation failed for #$issueNum" -Context $_.Exception.Message
        }
    } else {
        Add-WorkingQueueItem -State $GlobalState -IssueNumber $issueNum -IssueTitle $issueTitle -AgentProvider $targetAgent
        $delegatedInThisRun.Add($issueNum) | Out-Null
        if ($null -ne $GlobalState.escalated_issues) {
            $esc = $GlobalState.escalated_issues | Where-Object { [int]$_.issue_number -eq $issueNum }
            if ($esc) {
                $esc.status = "RETRY_DISPATCHED"
            }
        }
        Save-AutopilotState -State $GlobalState
    }
}

$SubState.status = "completed"
