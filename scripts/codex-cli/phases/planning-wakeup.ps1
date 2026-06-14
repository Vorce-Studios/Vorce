# scripts/codex-cli/phases/planning-wakeup.ps1
# Planning Mode: Scan issues, create new ones, delegate to Jules

Set-StrictMode -Version Latest

function Add-WorkingQueueItem {
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
        Write-Host "[PLANNING] Working Session fuer Issue #$IssueNumber ist bereits geplant." -ForegroundColor DarkGray
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
    Write-Host "[PLANNING] Working Session geplant: Issue #$IssueNumber -> $AgentProvider" -ForegroundColor Cyan
}

function Invoke-PlanningWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $State = Update-AutopilotStateObject -State $State
    Confirm-WorkingSessionsState -State $State
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

            $issueNum = [int]$_.number
            $isEscalatedRetry = $false
            if ($null -ne $State.escalated_issues) {
                $esc = $State.escalated_issues | Where-Object { [int]$_.issue_number -eq $issueNum }
                if ($esc -and ($esc.status -eq "QUEUED_FOR_RETRY" -or $esc.status -eq "RESOLVED_BY_PLANNING")) {
                    $isEscalatedRetry = $true
                }
            }

            $hasExistingJulesSession = ($body -match "<!--\s*jules-session-id:") -or ($body -match "<!--\s*jules-session-name:") -or ($body -match "<!--\s*vorce-queue-state:\s*dispatched")
            $hasInclude -and (-not $hasExclude) -and (-not $isMasterIssue) -and (-not $hasExistingJulesSession -or $isEscalatedRetry)
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

            Write-Host "[PLANNING] Re-Planning fuer eskaliertes Issue #$issueNum ($issueTitle) via CEO + QA-Auditor Deliberation..." -ForegroundColor Yellow

            $promptText = @"
Das Issue #$issueNum ("$issueTitle") wurde an Jules delegiert (letzte Session: $lastSessionId), ist aber im Monitoring-Modus fehlgeschlagen oder hängengeblieben (Timeout/Fehler).

Deine Rolle: Analysiere diese Eskalation im CEO + QA-Auditor Team.
Erstelle eine neue, präzisere Handlungsanweisung (Prompt-Ergänzung oder überarbeitete Issue-Beschreibung), um Jules beim nächsten Versuch erfolgreich zu leiten.
Antworte mit einem konkreten, korrigierten Handlungsplan für Jules.
"@

            # Erzwinge CEO + QA-Auditor Deliberation
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
                            Write-Host "[PLANNING]   -> Konflikt-Issue #$newIssueNum erfolgreich erstellt! Zuweisung an $targetAgent." -ForegroundColor Green

                            if ($null -eq $State.autopilot_created_issues) { $State.autopilot_created_issues = @() }
                            $State.autopilot_created_issues += [ordered]@{ tag = $conflictTag; issue_number = $newIssueNum; created_at = (Get-Date -Format 'o') }

                            Add-WorkingQueueItem -State $State -IssueNumber $newIssueNum -IssueTitle $issueTitle -AgentProvider $targetAgent
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

    # --- Step 2: Check if we should create new issues ---
    $newIssues = @()
    $runIssueCreation = $false

    if ($Config.PSObject.Properties.Name -contains "planning_sequence") {
        Write-Host "[PLANNING] Starte sequentielle Planungs-Sequenz (Session Splitting)..." -ForegroundColor Yellow
        $planningContext = ""

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
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

            $stepResult = $null
            if ($step.id -eq "final_synthesis" -or $step.prompt_ref -eq "planning_synthesis") {
                Write-Host "[PLANNING] Starte Planning Synthesis als interaktiven Codex-Chat." -ForegroundColor Cyan
                $sessionResult = Invoke-AutopilotCodexSession `
                    -SessionType "planning-synthesis" `
                    -Prompt $fullPrompt `
                    -State $State `
                    -Model "gpt-5.5" `
                    -VisibleTerminal `
                    -ResumeMainSession `
                    -DryRun:$DryRun

                $isSessionDryRun = ($sessionResult.PSObject.Properties.Name -contains "DryRun") -and [bool]$sessionResult.DryRun
                $sessionOutput = if ($isSessionDryRun) {
                    "{`"dry_run`":true}"
                } elseif ($sessionResult.PSObject.Properties.Name -contains "Output" -and -not [string]::IsNullOrWhiteSpace([string]$sessionResult.Output)) {
                    [string]$sessionResult.Output
                } else {
                    "Interactive planning synthesis completed."
                }
                $stepResult = [pscustomobject]@{
                    success = [bool]$sessionResult.Success
                    output  = $sessionOutput
                }
            } else {
                $stepResult = Invoke-DualCeoTask `
                    -QuotaRegistry $QuotaRegistry `
                    -Config $Config `
                    -TaskType "planning" `
                    -Prompt $fullPrompt `
                    -State $State `
                    -DryRun:$DryRun
            }

            if ($stepResult.success) {
                $output = [string]$stepResult.output
                $planningContext += "`n### Ergebnis von $($step.label):`n$output`n"

                if ($step.id -eq "task_generation" -or $step.prompt_ref -eq "planning_proposal") {
                    try {
                        $parsedObj = $null
                        try {
                            $parsedObj = $output | ConvertFrom-Json
                        } catch {
                            $jsonArrMatch = [regex]::Match($output, '(?s)\[.*\]')
                            if ($jsonArrMatch.Success) {
                                try { $parsedObj = $jsonArrMatch.Value | ConvertFrom-Json } catch {}
                            }
                        }
                        if ($null -ne $parsedObj) {
                            $runIssueCreation = $true
                            if ($parsedObj -is [System.Array] -or $parsedObj -is [System.Collections.IList]) {
                                $newIssues += @($parsedObj)
                            } elseif ($parsedObj.PSObject.Properties.Name -contains "proposal") {
                                $newIssues += @($parsedObj.proposal)
                            }
                        }
                    } catch {
                        Write-Warning "[PLANNING] Fehler beim Parsen der vorgeschlagenen Issues in $($step.label): $_"
                    }
                }
            } else {
                Write-Warning "[PLANNING] Schritt $($step.label) fehlgeschlagen."
            }
        }
    } else {
        # Fallback to single-phase planning
        if ($candidates.Count -lt 3) {
            Write-Host "[PLANNING] Wenige offene Issues - pruefe ob neue erstellt werden sollten." -ForegroundColor Yellow

            # Lade die Issues aus dem Cache fuer den Prompt-Kontext
            $cachedIssuePath = Join-Path $ScriptDir "dashboard\public\github-issues.json"
            $promptIssuesContext = ""
            if (Test-Path $cachedIssuePath) {
                try {
                    $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $gateIssueNumbers = @(651, 650, 547, 549, 548, 661, 662, 96, 98, 99, 101, 102, 103, 654, 655, 656, 657, 658, 659, 107, 43, 652, 653)
                    $contextLines = @()

                    if ($null -ne $issuesRaw -and ($issuesRaw -is [System.Array] -or $issuesRaw -is [System.Collections.IList])) {
                        foreach ($issue in $issuesRaw) {
                            if ($gateIssueNumbers -contains $issue.number) {
                                $title = $issue.title
                                $issueState = $issue.state
                                $bodySnippet = if ($issue.body -and $issue.body.Length -gt 250) { $issue.body.Substring(0, 250) + "..." } else { $issue.body }
                                $bodySnippet = $bodySnippet -replace "`n", " " -replace "`r", ""
                                $contextLines += "- #$($issue.number) [$issueState]: $title (Auszug: $bodySnippet)"
                            }
                        }
                    }

                    if ($contextLines.Count -gt 0) {
                        $promptIssuesContext = "`n`nHier sind die verfuegbaren Details zu den genannten Gate-Issues (aus dem lokalen Cache):`n" + ($contextLines -join "`n")
                    }
                } catch {
                    Write-Warning "[PLANNING] Fehler beim Laden des Issue-Contexts fuer den Prompt: $_"
                }
            }

            $promptText = @"
Du bist der Autopilot fuer das Vorce-Projekt (Rust Projection-Mapping Software).
Repository: $repo

Aktuell gibt es nur $($candidates.Count) offene, delegierbare Issues.

WICHTIGE ANWEISUNG ZU MCP-TOOLS:
Du hast hier alle benoetigten Informationen direkt im Text.
VERWENDE KEINE GITHUB-MCP-TOOLS (wie github_fetch_issue oder github_search_issues)! Das kostet nur unnoetig Zeit und Token. Arbeite AUSSCHLIESSLICH mit den Daten aus diesem Prompt.

Plane strikt Richtung Release 1.0 Readiness. Massgeblicher Top-Level-Kompass ist:
- #651 VOR-002_MAIs_Release-1.0-Readiness-Gate

Priorisiere neue Aufgaben nur aus diesen Gate-Lanes:
1. UI-Test-Automation: #650, #547, #549, #548
2. Timeline/Show-Control Acceptance: #661, #662, #96, #98, #99, #101, #102, #103
3. Cluster/Multi-Instance Scope-Freeze: #654, #655, #656, #657, #658, #659
4. NDI/Asset-Verfuegbarkeit: #107
5. macOS-CI/Smoke-Validation: #43
6. Packaging/Install-Sanity und Scope-Freeze: #652, #653
$promptIssuesContext

Schlage bis zu $($Config.max_issues_per_planning_cycle) konkrete, kleine Issues vor.
Keine generischen TODO-, Refactoring- oder Performance-Issues erzeugen, wenn sie nicht direkt eines der Release-Gates beweisbar voranbringen.
Keine Master-Issues als Jules-Coding-Task erzeugen. Coding-/QA-Aufgaben muessen Standard- oder Sub-Issues sein und die Namenskonvention einhalten.

WICHTIG ZUR AGENT-ZUWEISUNG:
Du MUSST für jedes Issue gezielt entscheiden, welcher Agent es bearbeitet.
- "jules": NUR für riesige Refactorings, UI-Architektur oder Multi-File Features nutzen.
- Lokale CLI-Agents (z.B. "gemini_cli", "claude_code"): ZWINGEND zu nutzen für kleine Bugfixes, isolierte Modul-Anpassungen, Scripts, CI/CD-Fixes oder klar umrissene Algorithmen! Du SOLLST regelmäßig Aufgaben an diese CLI-Agents delegieren, um Jules zu entlasten!
Verfügbare Agents: $agentsStr

Antworte NUR mit einer JSON-Liste im Format:
[{"title": "__VOR-000_SubI_Issue-Title", "body": "Beschreibung mit Parent-Issue und Acceptance-Evidence", "labels": ["jules-task", "priority: high", "testing"], "agent": "<agent_name_hier_eintragen>"}]

Wenn keine neuen Issues noetig sind, antworte mit einem leeren Array.
"@
            $planResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "planning" -DryRun:$DryRun -Prompt $promptText -State $State

            if ($planResult.success) {
                try {
                    $parsedObj = $null
                    try {
                        $parsedObj = $planResult.output | ConvertFrom-Json
                    } catch {
                        $jsonObjMatch = [regex]::Match($planResult.output, '(?s)\{.*\}')
                        if ($jsonObjMatch.Success) {
                            try { $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json } catch {}
                        }
                        if ($null -eq $parsedObj) {
                            $jsonArrMatch = [regex]::Match($planResult.output, '(?s)\[.*\]')
                            if ($jsonArrMatch.Success) {
                                try { $parsedObj = $jsonArrMatch.Value | ConvertFrom-Json } catch {}
                            }
                        }
                    }

                    if ($null -ne $parsedObj) {
                        $runIssueCreation = $true
                        if ($parsedObj -is [System.Array] -or $parsedObj -is [System.Collections.IList]) {
                            $newIssues = @($parsedObj)
                        } elseif ($parsedObj.PSObject.Properties.Name -contains "proposal") {
                            $newIssues = @($parsedObj.proposal)
                        }
                    }
                } catch {
                    Write-Warning "[PLANNING] Konnte CLI-Antwort nicht parsen: $_"
                }
            }
        }
    }

    # Execute issue creation logic if issues were proposed
    if ($runIssueCreation -and $newIssues.Count -gt 0) {
        try {
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
                if ($null -eq $newIssue -or -not ($newIssue.PSObject.Properties.Name -contains "title")) { continue }
                $issueTitle = [string]$newIssue.title
                $issueBody = if ($newIssue.PSObject.Properties.Name -contains "body") { [string]$newIssue.body } else { "" }

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
                    $labels = @(if ($newIssue.PSObject.Properties.Name -contains "labels") { $newIssue.labels } else { @() }) + @($Config.issue_filters.autopilot_label)
                    if ($issueAgent -ne "jules") {
                        $labels = @($labels | Where-Object { $_ -ne "jules-task" })
                    }
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
        } catch {
            Write-Warning "[PLANNING] Fehler bei der Issue-Erstellung: $_"
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
            if ($targetAgent -eq "jules") {
                Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "dry-run-$issueNum" -AgentType $targetAgent -JobId "dry-run-job"
            } else {
                Add-WorkingQueueItem -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -AgentProvider $targetAgent
                Save-AutopilotState -State $State
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

                if ($null -ne $State.escalated_issues) {
                    $esc = $State.escalated_issues | Where-Object { [int]$_.issue_number -eq $issueNum }
                    if ($esc) {
                        $esc.status = "RETRY_DISPATCHED"
                        Save-AutopilotState -State $State
                    }
                }
            } catch {
                Write-Warning "[PLANNING] Jules Session fuer #$issueNum fehlgeschlagen: $_"
                Add-ErrorLog -State $State -Message "Jules delegation failed for #$issueNum" -Context $_.Exception.Message
            }
        } else {
            Add-WorkingQueueItem -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -AgentProvider $targetAgent
            $delegatedInThisRun.Add($issueNum) | Out-Null
            if ($null -ne $State.escalated_issues) {
                $esc = $State.escalated_issues | Where-Object { [int]$_.issue_number -eq $issueNum }
                if ($esc) {
                    $esc.status = "RETRY_DISPATCHED"
                }
            }
            Save-AutopilotState -State $State
        }
    }

    $State.last_planning_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[PLANNING] ========== Planning abgeschlossen ==========" -ForegroundColor Magenta
}
