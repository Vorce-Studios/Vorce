# Vorce-Autopilot/src/phases/planning-wakeup.ps1
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

function Test-AutopilotJulesIssueSafe {
    param(
        [AllowNull()][string]$Title,
        [AllowNull()][string]$Body
    )

    $titleText = if ($null -eq $Title) { "" } else { [string]$Title }
    $bodyText = if ($null -eq $Body) { "" } else { [string]$Body }

    if (
        $titleText -match "_MAIs_" -or
        $titleText -match "(?i)Resolve-Merge-Conflicts?|Merge-Konflikt|Merge-Conflict|Konflikt" -or
        $titleText -match "(?i)Release-Readiness|Merge-Reihenfolge|Blocker-Matrix|PRs?[-_\s]*\d|PR-\d"
    ) {
        return $false
    }

    $isTrackerLike = $bodyText -match "(?i)\bMaster-Issue\b|Tracking-PR|Tracker|buendelt|bündelt|Bündelung|Nachverfolgung|Scope-Freeze"
    $isExplicitSubTask = $titleText -match "(_SubI_|_StIs_|_User_)"
    if ($isTrackerLike -and -not $isExplicitSubTask) {
        return $false
    }

    if ($bodyText.Length -lt 250) {
        return $false
    }

    $hasScope = $bodyText -match "(?i)\b(Ziel|Goal|Scope|Beschreibung|Current problem|Acceptance|Acceptance-Evidence|Acceptance criteria|Definition of Done|Akzeptanz)\b"
    $hasCodeWork = $bodyText -match "(?i)(crates/|scripts/|docs/|resources/|\.rs\b|\.ps1\b|\.ts\b|\.tsx\b|test|fixture|script|command|implement|fix|refactor|module|UI|CI)"
    if (-not ($hasScope -and $hasCodeWork)) {
        return $false
    }

    return $true
}

function Test-PlanningJulesCapacityState {
    param([AllowNull()][string]$State)

    $normalized = if ([string]::IsNullOrWhiteSpace($State)) { "QUEUED" } else { [string]$State }
    return $normalized -in @("QUEUED", "PLANNING", "IN_PROGRESS", "AWAITING_PLAN_APPROVAL")
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
    $planningStartedAt = Get-Date
    $planningQueueBefore = @($State.working_queue).Count
    $planningDelegationsBefore = @($State.active_delegations).Count
    $planningIssuesBefore = @($State.autopilot_created_issues).Count
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

    # Increment planning run count
    if (-not ($State.PSObject.Properties.Name -contains "planning_run_count")) {
        $State | Add-Member -MemberType NoteProperty -Name "planning_run_count" -Value 0 -Force
    }
    $State.planning_run_count = [int]$State.planning_run_count + 1
    Save-AutopilotState -State $State

    $ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../..")
    $VarDbDir = Join-Path $ScriptDir "var/db"

    # Define script block to fetch candidates to avoid duplication
    $GetCandidates = {
        Write-Host "[PLANNING] Lade offene Issues..." -ForegroundColor Cyan

        $issues = @()
        try {
            # Use github-client wrapper
            $issues = Get-GitHubIssues -Repository $repo -Limit 50
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

            # Dual CEO Deliberation
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
                    $null = New-GitHubIssueComment -Repository $repo -IssueNumber $issueNum -Body $commentBody
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
        $prs = Get-GitHubPullRequests -Repository $repo -Limit 100
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
                    $issueBody = "## Ziel`n"
                    $issueBody += "Loese die Merge-Konflikte der unten gelisteten bestehenden PR-Branches gegen ihre jeweilige Base-Branch. Dieses Issue ist ein lokaler CLI-Agent-Auftrag und darf niemals an Jules delegiert werden.`n`n"
                    $issueBody += "## Betroffene PRs`n"
                    foreach ($cpr in $conflictingPrs) {
                        $baseRef = if (Test-ObjectProperty -Object $cpr -Name "baseRefName") { [string]$cpr.baseRefName } else { "main" }
                        $headRef = if (Test-ObjectProperty -Object $cpr -Name "headRefName") { [string]$cpr.headRefName } else { "" }
                        $issueBody += "- PR #$($cpr.number): `$headRef` -> `$baseRef` - $($cpr.title)`n"
                    }
                    $issueBody += @"

## Arbeitsanweisung fuer den lokalen Agenten
- Jeden PR einzeln pruefen: `gh pr view <nr> --json state,mergeable,headRefName,baseRefName,title,files`.
- Geschlossene oder nicht mehr konfliktierende PRs ueberspringen und im Abschlussbericht nennen.
- Fuer konfliktierende PRs: Head-Branch auschecken, Base-Branch mergen, Konfliktdateien mit `git diff --name-only --diff-filter=U` ermitteln, Konflikte minimal und fachlich passend aufloesen, Tests/Checks soweit sinnvoll ausfuehren, Commit auf denselben Head-Branch pushen.
- Keinen neuen PR erstellen und keinen leeren Commit erzeugen.
- Wenn ein PR inhaltlich nicht mehr rettbar ist, keine Jules-Session starten. Stattdessen im Abschlussbericht exakt PR, Branches, Konfliktdateien und Grund nennen.

## Akzeptanz
- Jeder noch offene konfliktierende PR aus der Liste ist entweder konfliktfrei gepusht oder konkret als nicht rettbar dokumentiert.
- Der Bericht nennt fuer jeden PR: Status, Branch, geaenderte Dateien, ausgefuehrte Checks.
- Es wurden keine Jules-Sessions und keine Tracking-PRs erzeugt.

Prioritaet: KRITISCH - blockiert Release-Pipeline.
"@

                    # EXKLUSIV fuer gemini_cli
                    $targetAgent = "gemini_cli"
                    $newIssueUrl = New-GitHubIssue -Repository $repo -Title $issueTitle -Body $issueBody -Labels @("priority: critical", "bug", "agent:$targetAgent")
                    if ($newIssueUrl -match "/issues/(\d+)") {
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
                (-not ($_.PSObject.Properties.Name -contains "agent_type") -or ($_.agent_type -eq "jules")) -and
                (Test-PlanningJulesCapacityState -State $(if ($_.PSObject.Properties.Name -contains "jules_state") { [string]$_.jules_state } else { "QUEUED" }))
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

            # Lade die Issues aus dem Cache (var/db) fuer den Prompt-Kontext
            $cachedIssuePath = Join-Path $VarDbDir "github-issues.json"
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
VERWENDE KEINE GITHUB-MCP-TOOLS! Arbeite AUSSCHLIESSLICH mit den Daten aus diesem Prompt.

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
Keine generischen TODO-, Refactoring- oder Performance-Issues erzeugen.
Keine Master-Issues als Jules-Coding-Task erzeugen.

WICHTIG ZUR AGENT-ZUWEISUNG:
Du MUSST für jedes Issue gezielt entscheiden, welcher Agent es bearbeitet.
- "jules": NUR für riesige Refactorings, UI-Architektur oder Multi-File Features.
- Lokale CLI-Agents (z.B. "gemini_cli", "claude_code"): ZWINGEND zu nutzen für kleine Bugfixes, isolierte Modul-Anpassungen, Scripts, CI/CD-Fixes.
Verfügbare Agents: $agentsStr

Antworte NUR mit einer JSON-Liste im Format:
[{"title": "__VOR-000_SubI_Issue-Title", "body": "Beschreibung", "labels": ["jules-task", "priority: high"], "agent": "<agent_name_hier_eintragen>"}]

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
            $cachedIssuePath = Join-Path $VarDbDir "github-issues.json"
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
                # Direct call fallback
                $existingVorIssues = Get-GitHubIssues -Repository $repo -Limit 300
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
                # Safe wrapping using jules-client
                $sessionId = New-JulesSession -IssueNumber $issueNum -Repository $repo -ApiKey $env:JULES_API_KEY -AutoCreatePr

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

    # --- Smart Memory Optimization (Triggered every 3rd planning run) ---
    if ($State.planning_run_count % 3 -eq 0 -and -not $DryRun.IsPresent) {
        Write-Host "[PLANNING] Jeder 3. Planungs-Lauf ($($State.planning_run_count)): Starte smarte Memory-Optimierung..." -ForegroundColor Yellow
        try {
            $memStore = Read-MemoryStore
            $memoriesJson = $memStore | ConvertTo-Json -Depth 15
            $journalPath = Get-AutopilotTaskJournalPath
            $journalContent = if (Test-Path $journalPath) { Get-Content $journalPath -Raw -Encoding UTF8 } else { "" }

            $promptText = @"
Du bist der CEO-Orchestrator für das Vorce-Autopilot Projekt.
Deine Aufgabe ist es, das Memory-System des Autopiloten zu pflegen, um die Effizienz zu steigern, Redundanzen abzubauen und den Tokenverbrauch zu senken.

Hier ist der aktuelle Inhalt des Memory-Systems (Erinnerungen):
$memoriesJson

Hier ist das aktuelle Task-Journal des Autopiloten:
$journalContent

Bitte analysiere diese Daten gründlich.
Entscheide:
1. Welche bestehenden Erinnerungen sind veraltet, redundant oder nicht mehr hilfreich und sollten entfernt werden? (Aktion: "remove")
2. Welche wichtigen neuen Erkenntnisse, Richtlinien oder kritischen System-Zustände aus dem Task-Journal oder den letzten Entwicklungen sollten als neue Erinnerung hinzugefügt werden? (Aktion: "add")
   - Neue Erinnerungen müssen sehr präzise, kompakt und von hoher Wichtigkeit sein.
   - Maximal 30 Erinnerungen sind insgesamt erlaubt.

Gib deine Entscheidung AUSSCHLIESSLICH als JSON-Liste von Aktionen im folgenden Format zurück (ohne Markdown-Formatierung, ohne zusätzlichen Text):
[
  { "action": "remove", "id": "mem-id-here" },
  { "action": "add", "text": "Erinnerungstext hier", "type": "permanent|temporary", "priority": "critical|high|medium" }
]

Wenn keine Änderungen notwendig sind, antworte mit einem leeren Array: []
"@

            $memResult = Invoke-DualCeoTask `
                -QuotaRegistry $QuotaRegistry `
                -Config $Config `
                -TaskType "analysis" `
                -Prompt $promptText `
                -State $State `
                -DryRun:$DryRun

            if ($memResult.success -and -not $DryRun.IsPresent) {
                $rawOutput = $memResult.output
                $actions = $null
                try {
                    $actions = $rawOutput | ConvertFrom-Json
                } catch {
                    $jsonArrMatch = [regex]::Match($rawOutput, '(?s)\[.*\]')
                    if ($jsonArrMatch.Success) {
                        try { $actions = $jsonArrMatch.Value | ConvertFrom-Json } catch {}
                    }
                }

                if ($null -ne $actions -and ($actions -is [System.Array] -or $actions -is [System.Collections.IList])) {
                    foreach ($act in $actions) {
                        if ($act.action -eq "remove" -and $act.id) {
                            Write-Host "[PLANNING] Smart Memory: Entferne Erinnerung $($act.id)" -ForegroundColor Yellow
                            Remove-Memory -Id $act.id
                        } elseif ($act.action -eq "add" -and $act.text) {
                            Write-Host "[PLANNING] Smart Memory: Fuege Erinnerung hinzu: $($act.text)" -ForegroundColor Green
                            $priority = if ($act.priority) { $act.priority } else { "medium" }
                            $type = if ($act.type) { $act.type } else { "temporary" }
                            Add-Memory -Text $act.text -Type $type -Priority $priority -Source "autopilot_smart_memory"
                        }
                    }
                } else {
                    Write-Warning "[PLANNING] Konnte Smart Memory Aktionen nicht parsen oder keine Aktionen vorgeschlagen."
                }
            }
        } catch {
            Write-Warning "Fehler bei smarter Memory-Optimierung: $_"
        }
    }

    # --- Optimizer Session (2x daily, every 12 hours) ---
    $runAnalysis = $false
    $forceOptimizer = $false
    if ((Test-ObjectProperty -Object $State -Name "run_control") -and (Test-ObjectProperty -Object $State.run_control -Name "force_optimizer") -and [bool]$State.run_control.force_optimizer) {
        $forceOptimizer = $true
        $runAnalysis = $true
    }
    if (-not ($State.PSObject.Properties.Name -contains "last_optimizer_analysis_at") -or [string]::IsNullOrWhiteSpace([string]$State.last_optimizer_analysis_at)) {
        $runAnalysis = $true
    } elseif (-not $forceOptimizer) {
        try {
            $lastAt = [datetimeoffset]::Parse([string]$State.last_optimizer_analysis_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $ageHours = ((Get-Date) - $lastAt.LocalDateTime).TotalHours
            if ($ageHours -ge 12) {
                $runAnalysis = $true
            }
        } catch {
            $runAnalysis = $true
        }
    }

    if ($runAnalysis -and -not $DryRun.IsPresent) {
        Write-Host "[OPTIMIZER] Starte Optimizer-Analyse..." -ForegroundColor Yellow
        try {
            $logFilePath = Join-Path $ScriptDir "var/log/autopilot-live.log"
            $latestLogLines = ""
            if (Test-Path $logFilePath) {
                try {
                    $latestLogLines = Get-Content $logFilePath -Tail 150 -ErrorAction SilentlyContinue | Out-String
                } catch {}
            }
            $stateJson = $State | ConvertTo-Json -Depth 15
            $quotaJson = $QuotaRegistry | ConvertTo-Json -Depth 15

            $promptText = @"
Du bist der Vorce-Autopilot Optimizer-Agent.
Deine Aufgabe ist es, die internen Abläufe, System-Prompts, Tokenverbrauch, Workflows, Session-Splitting und Auslastung des Autopiloten zu analysieren und konkrete Optimierungsvorschläge zu erarbeiten.

Hier ist der aktuelle Status des Autopiloten (State):
$stateJson

Hier ist die Quota-Registry (Kosten und Aufrufe):
$quotaJson

Hier sind die letzten 150 Zeilen der Logdatei (autopilot-live.log):
$latestLogLines

Bitte analysiere diese Statistiken und Logeinträge auf Ineffizienzen, Fehlerraten, hohe Tokenkosten oder Engpässe.
Schlage bis zu 3 konkrete Optimierungen vor. Jede Optimierung sollte einen klaren Titel, eine detaillierte Beschreibung des Problems, die erwartete Auswirkung (Impact) und die vorgeschlagene Aktion enthalten.

Gib deine Vorschläge AUSSCHLIESSLICH als JSON-Liste im folgenden Format zurück (ohne Markdown-Formatierung, ohne zusätzlichen Text):
[
  {
    "title": "Optimierung der System-Prompts für planning_synthesis",
    "description": "Die Analyse zeigt einen überdurchschnittlichen Tokenverbrauch...",
    "impact": "Senkung des Tokenverbrauchs um ca. 20%.",
    "proposed_action": "Erstelle ein Issue zur Überarbeitung des Prompts planning_synthesis.md"
  }
]

Wenn keine Optimierungen nötig oder sinnvoll sind, antworte mit einem leeren Array: []
"@

            $optResult = Invoke-DualCeoTask `
                -QuotaRegistry $QuotaRegistry `
                -Config $Config `
                -TaskType "analysis" `
                -Prompt $promptText `
                -State $State `
                -DryRun:$DryRun

            if ($optResult.success -and -not $DryRun.IsPresent) {
                $rawOutput = $optResult.output
                $proposals = $null
                try {
                    $proposals = $rawOutput | ConvertFrom-Json
                } catch {
                    $jsonArrMatch = [regex]::Match($rawOutput, '(?s)\[.*\]')
                    if ($jsonArrMatch.Success) {
                        try { $proposals = $jsonArrMatch.Value | ConvertFrom-Json } catch {}
                    }
                }

                if ($null -ne $proposals -and ($proposals -is [System.Array] -or $proposals -is [System.Collections.IList])) {
                    if (-not ($State.PSObject.Properties.Name -contains "optimizer_queue") -or $null -eq $State.optimizer_queue) {
                        $State | Add-Member -MemberType NoteProperty -Name "optimizer_queue" -Value @() -Force
                    }

                    $proposalList = @()
                    foreach ($p in $proposals) {
                        if ($p.title -and $p.description) {
                            $id = "opt-$(Get-Date -Format 'yyyyMMddHHmmss')-$([guid]::NewGuid().ToString('N').Substring(0, 4))"
                            $entry = [ordered]@{
                                id              = $id
                                title           = [string]$p.title
                                description     = [string]$p.description
                                impact          = [string]$p.impact
                                proposed_action = [string]$p.proposed_action
                                status          = "QUEUED"
                                created_at      = (Get-Date -Format 'o')
                            }
                            $State.optimizer_queue += @($entry)
                            $proposalList += @($entry)
                            Write-Host "[OPTIMIZER] Neuer Optimierungsvorschlag hinzugefügt: $($p.title)" -ForegroundColor Green
                        }
                    }

                    $State.last_optimizer_analysis_at = (Get-Date -Format 'o')
                    $nextOptimizerAt = (Get-Date).AddHours(12).ToString("o")
                    $previousApproved = @()
                    if (Test-ObjectProperty -Object $State -Name "optimizer_last_run" -and $null -ne $State.optimizer_last_run -and (Test-ObjectProperty -Object $State.optimizer_last_run -Name "approved_changes")) {
                        $previousApproved = @($State.optimizer_last_run.approved_changes)
                    }
                    $State | Add-Member -MemberType NoteProperty -Name "optimizer_last_run" -Value ([pscustomobject]@{
                        ran_at = $State.last_optimizer_analysis_at
                        next_run_at = $nextOptimizerAt
                        forced = $forceOptimizer
                        proposals = @($proposalList)
                        approved_changes = @($previousApproved | Select-Object -Last 10)
                        summary = if ($proposalList.Count -gt 0) { "$($proposalList.Count) Optimierungsvorschlaege erzeugt." } else { "Keine neuen Optimierungsvorschlaege." }
                    }) -Force
                    if (Test-ObjectProperty -Object $State -Name "run_control" -and $forceOptimizer) {
                        $State.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer" -Value $false -Force
                        $State.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer_requested_at" -Value $null -Force
                    }
                    Save-AutopilotState -State $State
                } else {
                    Write-Warning "[OPTIMIZER] Konnte Optimizer-Vorschläge nicht parsen oder keine Vorschläge generiert."
                    if (Test-ObjectProperty -Object $State -Name "run_control" -and $forceOptimizer) {
                        $State.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer" -Value $false -Force
                    }
                }
            }
        } catch {
            Write-Warning "Fehler bei Optimizer-Analyse: $_"
            if (Test-ObjectProperty -Object $State -Name "run_control" -and $forceOptimizer) {
                $State.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer" -Value $false -Force
            }
        }
    }

    $planningEndedAt = Get-Date
    $candidateCount = 0
    $candidateVar = Get-Variable -Name "candidates" -ErrorAction SilentlyContinue
    if ($null -ne $candidateVar -and $null -ne $candidateVar.Value) {
        $candidateCount = @($candidateVar.Value).Count
    }
    $queuedNow = @($State.working_queue).Count
    $delegationsNow = @($State.active_delegations).Count
    $createdIssuesNow = @($State.autopilot_created_issues).Count
    $planningSummary = "Issues geprueft: $candidateCount; Working-Queue: $planningQueueBefore -> $queuedNow; Delegierungen: $planningDelegationsBefore -> $delegationsNow; erstellte Issues gesamt: $createdIssuesNow."
    if (-not (Test-ObjectProperty -Object $State -Name "run_summaries") -or $null -eq $State.run_summaries) {
        $State | Add-Member -MemberType NoteProperty -Name "run_summaries" -Value ([pscustomobject]@{}) -Force
    }
    $State.run_summaries | Add-Member -MemberType NoteProperty -Name "planning" -Value ([pscustomobject]@{
        started_at = $planningStartedAt.ToString("o")
        completed_at = $planningEndedAt.ToString("o")
        duration_seconds = [int][Math]::Round(($planningEndedAt - $planningStartedAt).TotalSeconds)
        summary = $planningSummary
    }) -Force

    $State.last_planning_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[PLANNING] ========== Planning abgeschlossen ==========" -ForegroundColor Magenta
}
