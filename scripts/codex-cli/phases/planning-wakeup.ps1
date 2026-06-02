# scripts/codex-cli/phases/planning-wakeup.ps1
# Planning Mode: Scan issues, create new ones, delegate to Jules

Set-StrictMode -Version Latest

function Convert-PlanningProposalOutput {
    param([string]$Output)

    $newIssues = @()
    if ([string]::IsNullOrWhiteSpace($Output)) { return @() }

    $parsedObj = $null
    try {
        $parsedObj = $Output | ConvertFrom-Json
    } catch {
        $jsonArrMatch = [regex]::Match($Output, '(?s)\[.*\]')
        if ($jsonArrMatch.Success) {
            try { $parsedObj = $jsonArrMatch.Value | ConvertFrom-Json } catch {}
        }
        if ($null -eq $parsedObj) {
            $jsonObjMatch = [regex]::Match($Output, '(?s)\{.*\}')
            if ($jsonObjMatch.Success) {
                try { $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json } catch {}
            }
        }
    }

    if ($null -eq $parsedObj) { return @() }

    if ($parsedObj -is [System.Array] -or $parsedObj -is [System.Collections.IList]) {
        $newIssues = @($parsedObj)
    } elseif ($parsedObj.PSObject.Properties.Name -contains "proposal") {
        $propVal = $parsedObj.proposal
        if ($propVal -is [string]) {
            try { $newIssues = @($propVal | ConvertFrom-Json) } catch {}
        } else {
            $newIssues = @($propVal)
        }
    } elseif ($parsedObj.PSObject.Properties.Name -contains "response") {
        $respVal = $parsedObj.response
        if ($respVal -is [string]) {
            try {
                $nestedObj = $respVal | ConvertFrom-Json
                if ($nestedObj -is [System.Array] -or $nestedObj -is [System.Collections.IList]) {
                    $newIssues = @($nestedObj)
                } elseif ($nestedObj.PSObject.Properties.Name -contains "proposal") {
                    $newIssues = @($nestedObj.proposal)
                }
            } catch {
                $jsonMatch = [regex]::Match($respVal, '(?s)\[.*\]')
                if ($jsonMatch.Success) {
                    try { $newIssues = @($jsonMatch.Value | ConvertFrom-Json) } catch {}
                }
            }
        } else {
            $newIssues = @($respVal)
        }
    }

    return @($newIssues)
}

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
    if (-not ($State.PSObject.Properties.Name -contains "autopilot_created_issues")) {
        $State | Add-Member -MemberType NoteProperty -Name "autopilot_created_issues" -Value @() -Force
    }
    if (-not ($State.PSObject.Properties.Name -contains "active_delegations")) {
        $State | Add-Member -MemberType NoteProperty -Name "active_delegations" -Value @() -Force
    }
    if (-not ($State.PSObject.Properties.Name -contains "escalated_issues")) {
        $State | Add-Member -MemberType NoteProperty -Name "escalated_issues" -Value @() -Force
    }
    if (-not ($State.PSObject.Properties.Name -contains "decisions_pending")) {
        $State | Add-Member -MemberType NoteProperty -Name "decisions_pending" -Value @() -Force
    }

    # --- Step 0: Process Beta-Audit escalations via Alpha CEO first ---
    $auditAlphaEscalations = @($State.decisions_pending | Where-Object {
        $source = if ($_.PSObject.Properties.Name -contains "source") { [string]$_.source } else { "" }
        $owner = if ($_.PSObject.Properties.Name -contains "owner") { [string]$_.owner } else { "alpha_ceo" }
        $status = if ($_.PSObject.Properties.Name -contains "status") { [string]$_.status } else { "awaiting_alpha" }
        ($source -eq "audit" -or [string]$_.topic -match "Beta CEO") -and
        $owner -eq "alpha_ceo" -and
        $status -eq "awaiting_alpha"
    })

    if ($auditAlphaEscalations.Count -gt 0) {
        Write-Host "[PLANNING] Bearbeite $($auditAlphaEscalations.Count) Audit-Eskalation(en) zuerst via Alpha CEO." -ForegroundColor Yellow
        foreach ($decision in $auditAlphaEscalations) {
            $topic = [string]$decision.topic
            $context = [string]$decision.context
            $remediationCommand = if ($decision.PSObject.Properties.Name -contains "remediation_command") { [string]$decision.remediation_command } else { "" }
            $remediationResult = if ($decision.PSObject.Properties.Name -contains "remediation_result") { [string]$decision.remediation_result } else { "" }

            $alphaPrompt = @"
Du bist CEO ALPHA des Vorce-Autopiloten.
Eine Beta-CEO-Audit-Eskalation darf NICHT direkt an den User gehen. Du musst zuerst versuchen, einen zielfuehrenden Folgeplan zu erstellen.

Audit-Topic:
$topic

Audit-Kontext:
$context

Vorheriger Remediation-Versuch:
Command: $remediationCommand
Result: $remediationResult

Aufgabe:
1. Entscheide, ob Alpha CEO das Problem mit einem konkreten Plan, einer kleinen Working Session oder einem lokalen CLI-Tool zielfuehrend weiter bearbeiten kann.
2. Wenn ja, liefere einen knappen, konkreten Alpha-Plan.
3. Nur wenn Alpha nicht zielfuehrend helfen kann oder Owner-Rechte/Produktentscheidung zwingend sind, setze action="escalate_user" und erklaere exakt, was der User entscheiden/tun muss.

Antworte strikt als JSON:
{
  "action": "plan_fix|escalate_user",
  "alpha_response": "<konkreter Alpha-Plan oder Grund der Nicht-Loesbarkeit>",
  "next_step": "<naechster konkreter Schritt>",
  "user_escalation_reason": "<nur falls action=escalate_user>"
}
"@

            $alphaResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "planning" -Prompt $alphaPrompt -State $State -DryRun:$DryRun
            if ($alphaResult.success) {
                $parsedAlpha = $null
                try {
                    $parsedAlpha = $alphaResult.output | ConvertFrom-Json
                } catch {
                    $jsonMatch = [regex]::Match([string]$alphaResult.output, '(?s)\{.*\}')
                    if ($jsonMatch.Success) {
                        try { $parsedAlpha = $jsonMatch.Value | ConvertFrom-Json } catch {}
                    }
                }

                $alphaResponse = if ($parsedAlpha -and ($parsedAlpha.PSObject.Properties.Name -contains "alpha_response")) { [string]$parsedAlpha.alpha_response } else { [string]$alphaResult.output }
                $action = if ($parsedAlpha -and ($parsedAlpha.PSObject.Properties.Name -contains "action")) { [string]$parsedAlpha.action } else { "plan_fix" }
                $attempts = 0
                if ($decision.PSObject.Properties.Name -contains "alpha_attempts" -and $decision.alpha_attempts) {
                    $attempts = [int]$decision.alpha_attempts
                }

                $decision | Add-Member -MemberType NoteProperty -Name "alpha_response" -Value $alphaResponse -Force
                $decision | Add-Member -MemberType NoteProperty -Name "alpha_attempted_at" -Value (Get-Date -Format 'o') -Force
                $decision | Add-Member -MemberType NoteProperty -Name "alpha_attempts" -Value ($attempts + 1) -Force

                if ($action -eq "escalate_user") {
                    $reason = if ($parsedAlpha -and ($parsedAlpha.PSObject.Properties.Name -contains "user_escalation_reason")) { [string]$parsedAlpha.user_escalation_reason } else { $alphaResponse }
                    $decision | Add-Member -MemberType NoteProperty -Name "owner" -Value "user" -Force
                    $decision | Add-Member -MemberType NoteProperty -Name "status" -Value "awaiting_user" -Force
                    $decision | Add-Member -MemberType NoteProperty -Name "process_stage" -Value "user_decision" -Force
                    $decision | Add-Member -MemberType NoteProperty -Name "escalation_level" -Value "user" -Force
                    $decision | Add-Member -MemberType NoteProperty -Name "user_escalation_reason" -Value $reason -Force
                    Write-Host "[PLANNING] Alpha CEO eskaliert '$topic' an User." -ForegroundColor Red
                } else {
                    $decision | Add-Member -MemberType NoteProperty -Name "owner" -Value "alpha_ceo" -Force
                    $decision | Add-Member -MemberType NoteProperty -Name "status" -Value "alpha_action_proposed" -Force
                    $decision | Add-Member -MemberType NoteProperty -Name "process_stage" -Value "alpha_remediation_planned" -Force
                    $decision | Add-Member -MemberType NoteProperty -Name "escalation_level" -Value "alpha" -Force
                    Write-Host "[PLANNING] Alpha CEO hat Folgeplan fuer '$topic' erstellt." -ForegroundColor Green
                }
            } else {
                Write-Warning "[PLANNING] Alpha-Review fuer Audit-Eskalation '$topic' fehlgeschlagen."
            }
        }

        if (-not $DryRun.IsPresent) {
            Save-AutopilotState -State $State
        }
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
                # Check if a conflict-resolution issue was already created in the last 24 hours
                $recentConflictIssue = $false
                if ($null -ne $State.autopilot_created_issues) {
                    foreach ($entry in $State.autopilot_created_issues) {
                        $isConflictTag = $false
                        if ((Test-ObjectProperty -Object $entry -Name "tag") -and [string]$entry.tag -match "^resolve-conflicts-") {
                            $isConflictTag = $true
                        }
                        if ($isConflictTag -and (Test-ObjectProperty -Object $entry -Name "created_at")) {
                            try {
                                $createdAt = [datetimeoffset]::Parse([string]$entry.created_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                $ageHours = ((Get-Date) - $createdAt.LocalDateTime).TotalHours
                                if ($ageHours -lt 24) {
                                    $recentConflictIssue = $true
                                    Write-Host "[PLANNING]   Merge-Konflikt-Issue wurde vor $([Math]::Round($ageHours,1))h erstellt (Issue #$($entry.issue_number)). Ueberspringe Neuerstellung." -ForegroundColor DarkGray
                                    break
                                }
                            } catch {}
                        }
                    }
                }

                if (-not $recentConflictIssue) {
                    $prNumbers = @($conflictingPrs | Sort-Object number | ForEach-Object { $_.number }) -join "-"
                    $conflictTag = "resolve-conflicts-$prNumbers"
                    Write-Host "[PLANNING]   Erstelle gebuendeltes Konflikt-Issue fuer $($conflictingPrs.Count) Konflikte" -ForegroundColor Yellow

                    if (-not $DryRun.IsPresent) {
                        $issueTitle = "MF-StIs_Resolve-Merge-Conflicts: PRs $($prNumbers -replace '-', ', ')"
                        $issueBody = "Die folgenden Pull Requests haben Merge-Konflikte:`n`n"
                        foreach ($cpr in $conflictingPrs) {
                            $issueBody += "- PR #$($cpr.number) ($($cpr.headRefName)): $($cpr.title)`n"
                        }
                        $issueBody += "`nBitte alle Konflikte manuell auflösen (Branches auschecken, main mergen, Konflikte beheben, pushen).`n"
                        $issueBody += "`nPrioritaet: KRITISCH - blockiert Release-Pipeline."

                        # EXKLUSIV fuer gemini_cli
                        $targetAgent = "gemini_cli"
                        $newIssueUrl = gh issue create --repo $repo --title $issueTitle --body $issueBody --label "priority: critical,bug,agent:$targetAgent" 2>&1
                        if ($LASTEXITCODE -eq 0 -and $newIssueUrl -match "/issues/(\d+)") {
                            $newIssueNum = [int]$Matches[1]
                            Write-Host "[PLANNING]   -> Konflikt-Issue #$newIssueNum erfolgreich erstellt! Delegiere ZWINGEND an lokalen CLI-Agenten ($targetAgent)" -ForegroundColor Green

                            if ($null -eq $State.autopilot_created_issues) { $State.autopilot_created_issues = @() }
                            $State.autopilot_created_issues += [ordered]@{ tag = $conflictTag; issue_number = $newIssueNum; created_at = (Get-Date -Format 'o') }

                            try {
                                $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
                                $quotaRegistryPath = Join-Path $ScriptDir "quota-registry.json"
                                $ToolsDir = Join-Path $ScriptDir "tools"
                                $cmdArgs = "-NoExit", "-File", "`"$ToolsDir\run-visible-agent-task.ps1`"", "-IssueNumber", $newIssueNum, "-IssueTitle", "`"$issueTitle`"", "-AgentProvider", "`"$targetAgent`"", "-Repository", "`"$repo`"", "-QuotaRegistryPath", "`"$quotaRegistryPath`""
                                $proc = Start-Process pwsh -ArgumentList $cmdArgs -PassThru -WindowStyle Normal
                                Add-Delegation -State $State -IssueNumber $newIssueNum -IssueTitle $issueTitle -JulesSessionId "local-agent-$($proc.Id)" -AgentType $targetAgent -JobId $($proc.Id.ToString())
                            } catch {
                                Write-Warning "[PLANNING] Lokaler Agent $targetAgent fuer #$newIssueNum fehlgeschlagen: $_"
                            }

                            Save-AutopilotState -State $State
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

    # --- Step 2: Sequential Planning Sequence (Session Splitting) ---
    $planningContext = ""
    $newIssues = @()

    if ($Config.PSObject.Properties.Name -contains "planning_sequence") {
        foreach ($step in $Config.planning_sequence) {
            Write-Host "[PLANNING] Starte Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan

            $promptVars = @{
                repo      = $repo
                context   = $planningContext
                maxIssues = $Config.max_issues_per_planning_cycle
                slots     = $julesAvailableSlots
            }

            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

            $stepResult = Invoke-DualCeoTask `
                -QuotaRegistry $QuotaRegistry `
                -Config $Config `
                -TaskType "planning" `
                -DryRun:$DryRun `
                -Prompt $fullPrompt `
                -State $State `
                -AlphaTierOverride $step.tier `
                -BetaTierOverride $step.tier

            if ($stepResult.success) {
                $output = [string]$stepResult.output
                $planningContext += "`n### Ergebnis von $($step.label):`n$output`n"

                # Wenn es der Propose-Schritt ist, Issues extrahieren
                if ($step.id -eq "propose_issues") {
                    $stepIssues = @(Convert-PlanningProposalOutput -Output $output)
                    $newIssues += $stepIssues
                    Write-Host "[PLANNING] $($stepIssues.Count) Issues vorgeschlagen." -ForegroundColor DarkGray
                }
            } else {
                Write-Warning "[PLANNING] Schritt $($step.id) fehlgeschlagen: $($stepResult.error)"
            }
        }
    }

                if ($newIssues.Count -gt 0) {
                    $newIssuesCreated = $false

                    # Use cached issue data from the dashboard instead of calling GitHub directly
                    $cachedIssuePath = Join-Path $ScriptDir "dashboard\public\github-issues.json"
                    $existingVorIssues = @()
                    $issuesRaw = $null

                    if (Test-Path $cachedIssuePath) {
                        try {
                            $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
                        } catch {
                            Write-Warning "[PLANNING] Fehler beim Lesen der gecachten Issues: $_"
                        }
                    }

                    if ($null -ne $issuesRaw -and ($issuesRaw -is [System.Array] -or $issuesRaw -is [System.Collections.IList])) {
                        $existingVorIssues = @($issuesRaw | Where-Object { $_.repo -eq $repo })
                        Write-Host "[PLANNING] Gecachte Issue-Daten zur VOR-Nummernermittlung geladen." -ForegroundColor DarkGray
                    } else {
                        Write-Host "[PLANNING] Lade Issues direkt via gh-cli zur VOR-Nummernermittlung (Fallback)..." -ForegroundColor DarkGray
                        $existingVorIssuesRaw = gh issue list --repo $repo --state all --json title --limit 300 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            try { $existingVorIssues = @($existingVorIssuesRaw | Out-String | ConvertFrom-Json) } catch {}
                        }
                    }

                    $nextVorNumber = 1
                    try {
                        $usedVorNumbers = @($existingVorIssues | ForEach-Object {
                            $m = [regex]::Match([string]$_.title, 'VOR-(\d{3})')
                            if ($m.Success) { [int]$m.Groups[1].Value }
                        })
                        if ($usedVorNumbers.Count -gt 0) {
                            $nextVorNumber = ([int]($usedVorNumbers | Measure-Object -Maximum).Maximum) + 1
                        }
                    } catch {
                        Write-Warning "[PLANNING] Konnte naechste VOR-Issue-Nummer nicht aus GitHub ermitteln; starte bei VOR-001."
                    }

                    $seenTitles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    if ($null -ne $existingVorIssues) {
                        foreach ($ei in $existingVorIssues) {
                            if (-not [string]::IsNullOrWhiteSpace($ei.title)) {
                                $seenTitles.Add([string]$ei.title) | Out-Null
                            }
                        }
                    }

                    foreach ($newIssue in $newIssues) {
                        # Validate that newIssue has a title
                        if ($null -eq $newIssue -or -not ($newIssue.PSObject.Properties.Name -contains "title")) { continue }
                        $issueTitle = [string]$newIssue.title
                        $issueBody = [string]$newIssue.body

                        if ($issueTitle -match "VOR-000") {
                            $issueTitle = $issueTitle -replace "VOR-000", ("VOR-{0:D3}" -f $nextVorNumber)
                            $nextVorNumber++
                        } elseif ($issueTitle -notmatch "^(VOR-\d{3}_(MAIs|StIs|User)_|__VOR-\d{3}_SubI_)") {
                            $issueSlug = ($issueTitle -replace "^[A-Za-z]+-[A-Za-z]+_", "") -replace "\s+", "-"
                            $issueTitle = "__VOR-{0:D3}_SubI_{1}" -f $nextVorNumber, $issueSlug
                            $nextVorNumber++
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

                        if ($DryRun.IsPresent) {
                            Write-Host "[PLANNING] [DRY RUN] Wuerde Issue erstellen: $issueTitle ($issueAgent)" -ForegroundColor DarkYellow
                        } else {
                            $labels = @($newIssue.labels) + @($Config.issue_filters.autopilot_label)

                            # Ensure jules-task label is removed if not jules
                            if ($issueAgent -ne "jules") {
                                $labels = @($labels | Where-Object { $_ -ne "jules-task" })
                            }
                            # Add agent label for tracking
                            $labels += "agent:$issueAgent"

                            $labelArgs = ($labels | ForEach-Object { "--label `"$_`"" }) -join " "
                            $createCmd = "gh issue create --repo $repo --title `"$issueTitle`" --body `"$issueBody`" $labelArgs"
                            $created = Invoke-Expression $createCmd 2>&1
                            Write-Host "[PLANNING] Issue erstellt: $created (Agent: $issueAgent)" -ForegroundColor Green
                            $State.autopilot_created_issues += @($issueTitle)
                            $newIssuesCreated = $true
                        }
                    }
                    if ($newIssuesCreated) {
                        Write-Host "[PLANNING] Neue Issues wurden erstellt. Lade Kandidatenliste neu..." -ForegroundColor Cyan
                        $candidates = @(& $GetCandidates)
                        Write-Host "[PLANNING] $($candidates.Count) Issues bereit fuer Delegation (nach Reload)." -ForegroundColor Green
                    }
                }
    }

    # --- Step 3: Delegate to Jules or local CLI Agents ---
    $julesProvider = $QuotaRegistry.providers.jules
    $currentSessions = [int]$julesProvider.usage_today.calls
    $maxDaily = [int]$Config.jules.max_daily_sessions
    $maxConcurrent = [int]$Config.jules.max_concurrent_sessions
    $activeDelegations = if ($null -ne $State -and $State.PSObject.Properties.Match("active_delegations").Count -gt 0 -and $null -ne $State.active_delegations) { @($State.active_delegations) } else { @() }
    $julesActiveCount = @($activeDelegations | Where-Object {
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
                $promptHint = ""
                if ($issue.PSObject.Properties.Name -contains "body" -and -not [string]::IsNullOrWhiteSpace([string]$issue.body)) {
                    $promptHint = ([string]$issue.body).Trim()
                    if ($promptHint.Length -gt 280) { $promptHint = $promptHint.Substring(0, 280) }
                }

                # Start visible terminal process
                $cmdArgs = "-NoExit", "-File", "`"$ToolsDir\run-visible-agent-task.ps1`"", "-IssueNumber", $issueNum, "-IssueTitle", "`"$issueTitle`"", "-AgentProvider", "`"$targetAgent`"", "-Repository", "`"$repo`"", "-QuotaRegistryPath", "`"$quotaRegistryPath`"", "-PromptHint", "`"$promptHint`""

                $proc = Start-Process pwsh -ArgumentList $cmdArgs -PassThru -WindowStyle Normal

                Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "local-agent-$($proc.Id)" -AgentType $targetAgent -JobId $($proc.Id.ToString())
                if (-not ($State.PSObject.Properties.Name -contains "working_sessions")) {
                    $State | Add-Member -MemberType NoteProperty -Name "working_sessions" -Value @() -Force
                }
                $State.working_sessions += @([ordered]@{
                    id          = "working-$($proc.Id)"
                    issue_number = $issueNum
                    issue_title  = $issueTitle
                    provider     = $targetAgent
                    prompt_hint  = $promptHint
                    status       = "running"
                    started_at   = (Get-Date -Format 'o')
                    process_id   = $proc.Id
                })
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
