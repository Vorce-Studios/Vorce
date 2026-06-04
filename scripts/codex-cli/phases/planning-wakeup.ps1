# scripts/codex-cli/phases/planning-wakeup.ps1
# Planning Mode: Scan issues, create new ones, delegate to Jules

Set-StrictMode -Version Latest

function Invoke-PlanningWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[PLANNING] ========== Planning Wake-Up ==========" -ForegroundColor Blue

    # Ensure state arrays exist
    if ($null -eq $State.autopilot_created_issues) {
        $State | Add-Member -MemberType NoteProperty -Name "autopilot_created_issues" -Value @() -Force
    }
    if ($null -eq $State.active_delegations) {
        $State | Add-Member -MemberType NoteProperty -Name "active_delegations" -Value @() -Force
    }

    # Define script block to fetch candidates to avoid duplication
    $GetCandidates = {
        Write-Host "[PLANNING] Lade offene Issues..." -ForegroundColor Cyan


        $issuesRaw = gh issue list --repo $repo --state open --json number,title,labels,assignees,body --limit 50 2>&1
        $issues = @()
        try {
            $issues = @($issuesRaw | Out-String | ConvertFrom-Json | ForEach-Object { $_ })
        } catch {
            Write-Warning "Issue-Fetch fehlgeschlagen: $_"
        }

        # Filter by include labels
        $includeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($l in $Config.issue_filters.include_labels) { $includeSet.Add($l) | Out-Null }
        $excludeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($l in $Config.issue_filters.exclude_labels) { $excludeSet.Add($l) | Out-Null }

        $c = @($issues | Where-Object {
            $labelNames = @($_.labels | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
            $hasInclude = @($labelNames | Where-Object { $includeSet.Contains($_) }).Count -gt 0
            $hasExclude = @($labelNames | Where-Object { $excludeSet.Contains($_) }).Count -gt 0
            $title = [string]$_.title
            $body = [string]$_.body
            $isMasterIssue = $title -match "_MAIs_"
            $hasExistingJulesSession = ($body -match "<!--\s*jules-session-id:") -or ($body -match "<!--\s*jules-session-name:") -or ($body -match "<!--\s*vorce-queue-state:\s*dispatched")
            $hasInclude -and (-not $hasExclude) -and (-not $isMasterIssue) -and (-not $hasExistingJulesSession)
        })

        $releaseRank = @{
            "662" = 10
            "655" = 20
            "107" = 30
            "43"  = 40
            "652" = 50
            "653" = 60
        }
        $c = @($c | Sort-Object `
            @{ Expression = { $key = [string]$_.number; if ($releaseRank.ContainsKey($key)) { $releaseRank[$key] } else { 999 } } }, `
            @{ Expression = { [int]$_.number } })

        # Exclude already delegated issues
        $delegatedNumbers = @($State.active_delegations | ForEach-Object { [int]$_.issue_number })
        if ($delegatedNumbers.Count -gt 0) {
            $c = @($c | Where-Object {
                $val = $_.number
                if ($val -is [System.Collections.IList]) { $val = $val[0] }
                if ($null -eq $val) { $true } else { $delegatedNumbers -notcontains [int]$val }
            })
        }
        return $c
    }

    # --- Step 0: Process escalated issues (CEO Re-Planning) ---
    $escalated = @($State.escalated_issues | Where-Object { $_.status -eq "NEEDS_PLANNING" })
    if ($escalated.Count -gt 0) {
        Write-Host "[PLANNING] Gefunden: $($escalated.Count) eskalierte Issues zur Re-Planung." -ForegroundColor Yellow
        foreach ($escIssue in $escalated) {
            $issueNum = [int]$escIssue.issue_number
            $issueTitle = [string]$escIssue.issue_title
            $lastSessionId = [string]$escIssue.last_jules_session_id

            Write-Host "[PLANNING] Re-Planning fuer eskaliertes Issue #$issueNum ($issueTitle) via Dual-CEO Deliberation..." -ForegroundColor Yellow

            $promptText = @"
Das Issue #$issueNum ("$issueTitle") wurde an Jules delegiert (letzte Session: $lastSessionId), ist aber im Monitoring-Modus fehlgeschlagen oder hängengeblieben (Timeout/Fehler).

Deine Rolle: Analysiere diese Eskalation im Dual-CEO Team.
Erstelle eine neue, präzisere Handlungsanweisung (Prompt-Ergänzung oder überarbeitete Issue-Beschreibung), um Jules beim nächsten Versuch erfolgreich zu leiten.
Antworte mit einem konkreten, korrigierten Handlungsplan für Jules.
"@

            # Erzwinge Dual-CEO Deliberation
            $planResult = Invoke-DualCeoTask `
                -QuotaRegistry $QuotaRegistry `
                -Config $Config `
                -TaskType "planning" `
                -Prompt $promptText `
                -State $State `
                -ForceDeliberation `
                -DryRun:$DryRun

            if ($planResult.success) {
                $ceoPlan = $planResult.output
                Write-Host "[PLANNING] Re-Planning erfolgreich für #$issueNum." -ForegroundColor Green

                if (-not $DryRun.IsPresent) {
                    $commentBody = "CEO Re-Planning Handlungsplan für den nächsten Versuch:`n`n$ceoPlan"
                    gh issue comment $issueNum --repo $repo --body $commentBody | Out-Null
                    Write-Host "[PLANNING] CEO-Plan auf GitHub-Issue #$issueNum gepostet." -ForegroundColor Green

                    $escIssue.planning_resolutions = [int]$escIssue.planning_resolutions + 1
                    $escIssue.status = "RESOLVED_BY_PLANNING"
                    Save-AutopilotState -State $State
                }
            } else {
                Write-Warning "[PLANNING] Re-Planning fuer #$issueNum fehlgeschlagen."
            }
        }
    }
    # --- Step 0.5: Check for PR Conflicts ---
    Write-Host "[PLANNING] Pruefe auf ungeloeste PR Merge-Konflikte..." -ForegroundColor Cyan
    try {
        $prOutput = gh pr list --repo $repo --state open --json number,title,headRefName,statusCheckRollup,mergeable,labels --limit 100 2>&1
        if ($LASTEXITCODE -eq 0) {
            $prs = @($prOutput | Out-String | ConvertFrom-Json | ForEach-Object { $_ })
            $conflictingPrs = @($prs | Where-Object { $_.mergeable -eq "CONFLICTING" })

            if ($conflictingPrs.Count -gt 0) {
                foreach ($cpr in $conflictingPrs) {
                    $prNum = [int]$cpr.number
                    $conflictTag = "resolve-conflict-pr-$prNum"
                    
                    # Check if a conflict-resolution issue was already created for this PR in the last 24 hours
                    $recentConflictIssue = $false
                    if ($null -ne $State.autopilot_created_issues) {
                        foreach ($entry in $State.autopilot_created_issues) {
                            $isConflictTag = $false
                            if ((Test-ObjectProperty -Object $entry -Name "tag") -and [string]$entry.tag -eq $conflictTag) {
                                $isConflictTag = $true
                            }
                            if ($isConflictTag -and (Test-ObjectProperty -Object $entry -Name "created_at")) {
                                try {
                                    $createdAt = [datetimeoffset]::Parse([string]$entry.created_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                    $ageHours = ((Get-Date) - $createdAt.LocalDateTime).TotalHours
                                    if ($ageHours -lt 24) {
                                        $recentConflictIssue = $true
                                        Write-Host "[PLANNING]   Merge-Konflikt-Issue fuer PR #$prNum wurde vor $([Math]::Round($ageHours,1))h erstellt (Issue #$($entry.issue_number)). Ueberspringe." -ForegroundColor DarkGray
                                        break
                                    }
                                } catch {}
                            }
                        }
                    }

                    if (-not $recentConflictIssue) {
                        Write-Host "[PLANNING]   Erstelle Konflikt-Issue fuer PR #$prNum" -ForegroundColor Yellow

                        if (-not $DryRun.IsPresent) {
                            $issueTitle = "MF-StIs_Resolve-Merge-Conflict-PR-${prNum}: $($cpr.title)"
                            $issueBody = "Der Pull Request #$prNum ($($cpr.headRefName)) hat einen Merge-Konflikt.`n`nBitte den Konflikt auf dem Branch '$($cpr.headRefName)' beheben und die Änderungen pushen.`n"
                            $issueBody += "`nPrioritaet: KRITISCH - blockiert Release-Pipeline."

                            $targetAgent = "gemini_cli"
                            $newIssueUrl = gh issue create --repo $repo --title $issueTitle --body $issueBody --label "priority: critical,bug,agent:$targetAgent" 2>&1
                            if ($LASTEXITCODE -eq 0 -and $newIssueUrl -match "/issues/(\d+)") {
                                $newIssueNum = [int]$Matches[1]
                                Write-Host "[PLANNING]   -> Konflikt-Issue #$newIssueNum fuer PR #$prNum erfolgreich erstellt! Delegiere an $targetAgent" -ForegroundColor Green

                                if ($null -eq $State.autopilot_created_issues) { $State.autopilot_created_issues = @() }
                                $State.autopilot_created_issues += [ordered]@{ tag = $conflictTag; issue_number = $newIssueNum; created_at = (Get-Date -Format 'o') }

                                Add-WorkingQueueItem -State $State -IssueNumber $newIssueNum -IssueTitle $issueTitle -AgentProvider $targetAgent
                                Save-AutopilotState -State $State
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Warning "[PLANNING] PR-Konflikt-Check fehlgeschlagen: $_"
    }

    # --- Step 1: Fetch open issues ---
    $candidates = @(& $GetCandidates)
    Write-Host "[PLANNING] $($candidates.Count) Issues bereit fuer Delegation." -ForegroundColor Green

    # Get available coding agents
    $availableAgents = @("jules")
    $QuotaRegistry.providers.PSObject.Properties.Name | ForEach-Object {
        $providerObj = $QuotaRegistry.providers.$_
        if ($providerObj.PSObject.Properties.Name -contains "command") {
            $cmd = $providerObj.command
            if ($cmd -notmatch "gh|codex" -and $_ -ne "jules") { $availableAgents += $_ }
        }
    }
    $agentsStr = $availableAgents -join ", "

    # --- Step 2: Planning sequence and optional issue creation ---
    $newIssues = @()
    if ($Config.PSObject.Properties.Name -contains "planning_sequence") {
        Write-Host "[PLANNING] Starte sequentielle Planungs-Sequenz (Session Splitting)..." -ForegroundColor Yellow
        $planningContext = ""
        $lagebildText = ""
        try {
            $lagebildText = Get-VorceLagebildSummary -State $State -Config $Config -QuotaRegistry $QuotaRegistry
        } catch {
            Write-Warning "Konnte Lagebild-Zusammenfassung nicht generieren: $_"
        }

        foreach ($step in $Config.planning_sequence) {
            Write-Host "[PLANNING] Starte Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan
            $julesActiveCount = @($State.active_delegations | Where-Object {
                -not ($_.PSObject.Properties.Name -contains "agent_type") -or ($_.agent_type -eq "jules")
            }).Count
            $julesAvailableSlots = [int]$Config.jules.max_concurrent_sessions - $julesActiveCount
            if ($julesAvailableSlots -lt 0) { $julesAvailableSlots = 0 }

            $promptVars = @{
                repo      = $repo
                context   = $planningContext
                maxIssues = $Config.max_issues_per_planning_cycle
                slots     = $julesAvailableSlots
            }
            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$lagebildText`n`n$stepPrompt"

            if ($step.id -eq "final_synthesis" -or $step.prompt_ref -eq "planning_synthesis") {
                $stepResult = Invoke-AutopilotCodexSession -SessionType "planning-synthesis" -Prompt $fullPrompt -State $State -Model "gpt-5.5" -VisibleTerminal -ResumeMainSession -DryRun:$DryRun
                $output = if ($stepResult.PSObject.Properties.Name -contains "Output") { [string]$stepResult.Output } else { "Interactive planning synthesis completed." }
                $planningContext += "`n### Ergebnis von $($step.label):`n$output`n"
                continue
            }

            $stepResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "planning" -Prompt $fullPrompt -State $State -DryRun:$DryRun
            if ($stepResult.success) {
                $output = [string]$stepResult.output
                $planningContext += "`n### Ergebnis von $($step.label):`n$output`n"
                if ($step.id -eq "task_generation" -or $step.prompt_ref -eq "planning_proposal") {
                    try {
                        $jsonArrMatch = [regex]::Match($output, '(?s)\[.*\]')
                        if ($jsonArrMatch.Success) {
                            $newIssues = @($jsonArrMatch.Value | ConvertFrom-Json)
                        }
                    } catch {
                        Write-Warning "[PLANNING] Konnte Task-Generierung nicht als JSON-Liste parsen: $_"
                    }
                }
            } else {
                Write-Warning "[PLANNING] Schritt $($step.label) fehlgeschlagen: $($stepResult.output)"
            }
        }
    } elseif ($candidates.Count -lt 3) {
        Write-Host "[PLANNING] Wenige offene Issues - pruefe ob neue erstellt werden sollten." -ForegroundColor Yellow
        $promptText = Get-VorcePlanningIssueDiscoveryPrompt -Repository $repo -CandidateCount $candidates.Count -MaxIssues $Config.max_issues_per_planning_cycle
        $planResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "planning" -DryRun:$DryRun -Prompt $promptText -State $State
        if ($planResult.success) {
            try {
                $jsonArrMatch = [regex]::Match([string]$planResult.output, '(?s)\[.*\]')
                if ($jsonArrMatch.Success) {
                    $newIssues = @($jsonArrMatch.Value | ConvertFrom-Json)
                }
            } catch {
                Write-Warning "[PLANNING] Konnte CLI-Antwort nicht parsen: $_"
            }
        }
    }

    if ($newIssues.Count -gt 0) {
        $newIssuesCreated = $false
        foreach ($newIssue in $newIssues) {
            if ($null -eq $newIssue -or -not ($newIssue.PSObject.Properties.Name -contains "title")) { continue }
            $issueTitle = [string]$newIssue.title
            $issueBody = if ($newIssue.PSObject.Properties.Name -contains "body") { [string]$newIssue.body } else { "" }
            $issueAgent = if ($newIssue.PSObject.Properties.Name -contains "agent" -and -not [string]::IsNullOrWhiteSpace([string]$newIssue.agent)) { [string]$newIssue.agent } else { "jules" }
            $labels = @()
            if ($newIssue.PSObject.Properties.Name -contains "labels") { $labels += @($newIssue.labels) }
            $labels += @($Config.issue_filters.autopilot_label, "agent:$issueAgent")
            if ($issueAgent -ne "jules") {
                $labels = @($labels | Where-Object { $_ -ne "jules-task" })
            }
            $labels = @($labels | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

            if ($DryRun.IsPresent) {
                Write-Host "[PLANNING] [DRY RUN] Wuerde Issue erstellen: $issueTitle ($issueAgent)" -ForegroundColor DarkYellow
                continue
            }

            $labelArgs = ($labels | ForEach-Object { "--label `"$_`"" }) -join " "
            $createCmd = "gh issue create --repo $repo --title `"$issueTitle`" --body `"$issueBody`" $labelArgs"
            $created = Invoke-Expression $createCmd 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[PLANNING] Issue erstellt: $created (Agent: $issueAgent)" -ForegroundColor Green
                $State.autopilot_created_issues += @([ordered]@{ tag = "created-$issueTitle"; title = $issueTitle; created_at = (Get-Date -Format 'o') })
                $newIssuesCreated = $true
            } else {
                Write-Warning "[PLANNING] Issue-Erstellung fehlgeschlagen: $created"
            }
        }

        if ($newIssuesCreated) {
            Write-Host "[PLANNING] Neue Issues wurden erstellt. Lade Kandidatenliste neu..." -ForegroundColor Cyan
            $candidates = @(& $GetCandidates)
            Write-Host "[PLANNING] $($candidates.Count) Issues bereit fuer Delegation (nach Reload)." -ForegroundColor Green
        }
    }

    # --- Step 3: Delegate to Jules or local CLI Agents ---
    $julesProvider = $QuotaRegistry.providers.jules
    $currentSessions = [int]$julesProvider.usage_today.calls
    $maxDaily = [int]$Config.jules.max_daily_sessions
    $maxConcurrent = [int]$Config.jules.max_concurrent_sessions
    $julesActiveCount = @($State.active_delegations | Where-Object {
        -not ($_.PSObject.Properties.Name -contains "agent_type") -or ($_.agent_type -eq "jules")
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

    $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $JulesScriptDir = Join-Path (Split-Path -Parent $ScriptDir) "jules"
    $ToolsDir = Join-Path $ScriptDir "tools"

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

        Write-Host ("[PLANNING] Delegiere Issue #{0}: {1} an Agent: {2}" -f $issueNum, $issueTitle, $targetAgent) -ForegroundColor Green

        if ($DryRun.IsPresent) {
            Write-Host "[PLANNING] [DRY RUN] Wuerde $targetAgent Session starten." -ForegroundColor DarkYellow
            Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "dry-run-$issueNum" -AgentType $targetAgent -JobId "dry-run-job"
            continue
        }

        if ($targetAgent -eq "jules") {
            if ($julesAvailableSlots -le 0) {
                Write-Host "[PLANNING] Jules-Kontingent erschoepft, ueberspringe Issue #$issueNum." -ForegroundColor Yellow
                continue
            }
            $julesAvailableSlots--

            try {
                $julesCreateCmd = Join-Path $JulesScriptDir "create-jules-session.ps1"
                $sessionResult = & $julesCreateCmd `
                    -IssueNumber $issueNum `
                    -Repository $repo `
                    -AutoCreatePr `
                    -ApiKey $env:JULES_API_KEY

                $sessionId = "unknown"
                if ($sessionResult) {
                    if ($sessionResult -is [System.Array]) {
                        $targetObj = $sessionResult | Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "SessionId") -and $_.SessionId } | Select-Object -First 1
                        if ($targetObj) {
                            $sessionId = [string]$targetObj.SessionId
                        } else {
                            $lastObj = $sessionResult[-1]
                            if ($lastObj -and ($lastObj.PSObject.Properties.Name -contains "SessionId")) {
                                $sessionId = [string]$lastObj.SessionId
                            }
                        }
                    } elseif (($sessionResult.PSObject.Properties.Name -contains "SessionId") -and $sessionResult.SessionId) {
                        $sessionId = [string]$sessionResult.SessionId
                    }
                }
                Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId $sessionId -AgentType "jules"
                Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
            } catch {
                Write-Warning "[PLANNING] Jules Session fuer #$issueNum fehlgeschlagen: $_"
                Add-ErrorLog -State $State -Message "Jules delegation failed for #$issueNum" -Context $_.Exception.Message
            }
        } else {
            # Local CLI Agent
            try {
                $quotaRegistryPath = Join-Path $ScriptDir "quota-registry.json"

                # Start visible terminal process
                $cmdArgs = "-NoExit", "-File", "`"$ToolsDir\run-visible-agent-task.ps1`"", "-IssueNumber", $issueNum, "-IssueTitle", "`"$issueTitle`"", "-AgentProvider", "`"$targetAgent`"", "-Repository", "`"$repo`"", "-QuotaRegistryPath", "`"$quotaRegistryPath`""

                $proc = Start-Process pwsh -ArgumentList $cmdArgs -PassThru -WindowStyle Normal

                Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "local-agent-$($proc.Id)" -AgentType $targetAgent -JobId $($proc.Id.ToString())
                $delegatedInThisRun.Add($issueNum) | Out-Null

                Write-Host "[PLANNING] Lokaler Agent $targetAgent gestartet (PID: $($proc.Id))." -ForegroundColor Cyan
            } catch {
                Write-Warning "[PLANNING] Lokaler Agent $targetAgent fuer #$issueNum fehlgeschlagen: $_"
                Add-ErrorLog -State $State -Message "Local agent $targetAgent failed for #$issueNum" -Context $_.Exception.Message
            }
        }
    }

    $State.last_planning_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[PLANNING] ========== Planning abgeschlossen ==========" -ForegroundColor Magenta
}
