# src/runs/SUB-RUN/SUB-RUN-03_MR-01_Planning__Strategy.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-03 Strategy: Generiere neue Issues..." -ForegroundColor Cyan

$candidates = @()
if ($MainState -is [hashtable] -and $MainState.ContainsKey("PlanningCandidates")) {
    $candidates = @($MainState["PlanningCandidates"])
} elseif ($MainState.PSObject.Properties.Name -contains "PlanningCandidates") {
    $candidates = @($MainState.PlanningCandidates)
}
$repo = $Config.repository

# Sanity Check
if ($candidates.Count -ge $Config.max_issues_per_planning_cycle) {
    Write-Host "[SUB-RUN] Genug Issues ($($candidates.Count)) vorhanden. Strategy-Generierung übersprungen." -ForegroundColor DarkGray
    $SubState.status = "skipped"
    return
}

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"

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

$newIssues = @()
$runIssueCreation = $false

if ($Config.PSObject.Properties.Name -contains "planning_sequence") {
    Write-Host "[PLANNING] Starte sequentielle Planungs-Sequenz (Session Splitting)..." -ForegroundColor Yellow
    $planningContext = ""
    $codexExhausted = $false
    $idx = 1

    foreach ($step in $Config.planning_sequence) {
        Write-Host "[PLANNING] Starte Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan

        $julesActiveCount = @($GlobalState.active_delegations | Where-Object {
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
        $useCodex = ($step.id -eq "final_synthesis" -or $step.prompt_ref -eq "planning_synthesis") -and (-not $codexExhausted)

        if ($useCodex) {
            Write-Host "[PLANNING] Starte Planning Synthesis als interaktiven Codex-Chat." -ForegroundColor Cyan
            $partIdx = "{0:D2}" -f ($idx)
            $partName = "PART-RUN-$($partIdx)_SR-03_MR-01_Planning__$($step.label -replace '[^A-Za-z0-9]', '-')"
            $stepResult = Invoke-PartRun `
                -PartRunName $partName `
                -AgentType "codex_orchestrator" `
                -Prompt $fullPrompt `
                -SubState $SubState `
                -Config $Config `
                -QuotaRegistry $QuotaRegistry `
                -DryRun:$DryRun

            if (-not $stepResult.success) {
                Write-Host "[PLANNING] Codex-Session fehlgeschlagen (evtl. Limit erreicht). Wechsle fuer restliche Session auf Fallback (DualCeoTask)." -ForegroundColor Yellow
                $codexExhausted = $true
                $useCodex = $false
            }
        }

        if (-not $useCodex) {
            $partIdx = "{0:D2}" -f ($idx)
            $partName = "PART-RUN-$($partIdx)_SR-03_MR-01_Planning__$($step.label -replace '[^A-Za-z0-9]', '-')"
            $stepResult = Invoke-PartRun `
                -PartRunName $partName `
                -AgentType "CEO" `
                -Prompt $fullPrompt `
                -SubState $SubState `
                -Config $Config `
                -QuotaRegistry $QuotaRegistry `
                -DryRun:$DryRun
        }

        if ($stepResult.success) {
            $idx++
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
            Write-Warning "[PLANNING] Schritt $($step.label) fehlgeschlagen: $(Format-AutopilotTaskFailure -Result $stepResult)"
        }
    }
} else {
    # Fallback to single-phase planning
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

Plane strikt Richtung Release 1.0 Readiness. Verwende die bereits auf GitHub gepflegten Issue-Titel als verbindliche Referenz.

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

Vorce-Namenskonvention fuer neue Vorschlaege:
- Standard-Issue: `*D**-000_Task-Title` (`000` wird vom Autopilot durch die naechste freie ID ersetzt).
- Master-Issue: `M...-000_Task-Title`; nur vorschlagen, wenn ausdruecklich ein neuer grosser Tracker erforderlich ist.
- Sub-Issue: `___M-{ParentMasterID}_s{SubIndex}_Task-Title`; `parent_master_id` und `sub_index` muessen gesetzt sein.
- Keine alten `VOR-`, `__VOR-` oder `MF-StIs_` Titel erzeugen.

Antworte NUR mit einer JSON-Liste im Format:
[{"title": "*D**-000_Issue-Title", "issue_type": "default", "body": "Beschreibung", "labels": ["jules-task", "priority: high"], "agent": "<agent_name_hier_eintragen>"}]

Wenn keine neuen Issues noetig sind, antworte mit einem leeren Array.
"@
    $partName = "PART-RUN-04_SR-03_MR-01_Planning__IssueProposalFallback"
    $planResult = Invoke-PartRun `
        -PartRunName $partName `
        -AgentType "CEO" `
        -Prompt $promptText `
        -SubState $SubState `
        -Config $Config `
        -QuotaRegistry $QuotaRegistry `
        -DryRun:$DryRun

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

if (-not ($MainState.PSObject.Properties.Name -contains "ProposedIssues")) {
    $MainState | Add-Member -MemberType NoteProperty -Name "ProposedIssues" -Value @() -Force
}
$MainState.ProposedIssues = $newIssues

if (-not ($MainState.PSObject.Properties.Name -contains "RunIssueCreation")) {
    $MainState | Add-Member -MemberType NoteProperty -Name "RunIssueCreation" -Value $runIssueCreation -Force
} else {
    $MainState.RunIssueCreation = $runIssueCreation
}

$SubState.status = "completed"
$SubState.artifacts += @{
    type = "StrategyReport"
    timestamp = (Get-Date).ToString('o')
    proposed_issues = $newIssues.Count
}
