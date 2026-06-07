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
        (Test-VorceMasterIssueTitle -Title $titleText) -or
        $titleText -match "(?i)Resolve-Merge-Conflicts?|Merge-Konflikt|Merge-Conflict|Konflikt" -or
        $titleText -match "(?i)Release-Readiness|Merge-Reihenfolge|Blocker-Matrix|PRs?[-_\s]*\d|PR-\d"
    ) {
        return $false
    }

    $isTrackerLike = $bodyText -match "(?i)\bMaster-Issue\b|Tracking-PR|Tracker|buendelt|bündelt|Bündelung|Nachverfolgung|Scope-Freeze"
    $isExplicitSubTask = (Test-VorceSubIssueTitle -Title $titleText) -or (Test-VorceDefaultIssueTitle -Title $titleText)
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
        (Test-VorceMasterIssueTitle -Title $titleText) -or
        $titleText -match "(?i)Resolve-Merge-Conflicts?|Merge-Konflikt|Merge-Conflict|Konflikt" -or
        $titleText -match "(?i)Release-Readiness|Merge-Reihenfolge|Blocker-Matrix|PRs?[-_\s]*\d|PR-\d"
    ) {
        return $false
    }

    $isTrackerLike = $bodyText -match "(?i)\bMaster-Issue\b|Tracking-PR|Tracker|buendelt|bündelt|Bündelung|Nachverfolgung|Scope-Freeze"
    $isExplicitSubTask = (Test-VorceSubIssueTitle -Title $titleText) -or (Test-VorceDefaultIssueTitle -Title $titleText)
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

    if ($forceOptimizer) {
        Write-Host "[PLANNING] Manueller Optimizer-Run beendet. Ueberspringe restliches Planning." -ForegroundColor Cyan
        return
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
