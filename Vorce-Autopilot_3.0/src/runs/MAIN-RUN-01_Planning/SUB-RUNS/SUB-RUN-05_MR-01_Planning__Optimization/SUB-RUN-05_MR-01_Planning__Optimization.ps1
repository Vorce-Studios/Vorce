# src/runs/SUB-RUN/SUB-RUN-05_MR-01_Planning__Optimization.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-05 Optimization: Optimiere System und Memory..." -ForegroundColor Cyan

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")

# --- Smart Memory Optimization ---
$optRuns = if ($Config.wake_intervals.PSObject.Properties.Name -contains "memory_optimization_runs" -and $Config.wake_intervals.memory_optimization_runs) { [int]$Config.wake_intervals.memory_optimization_runs } else { 3 }
if ($optRuns -gt 0 -and $GlobalState.planning_run_count % $optRuns -eq 0 -and -not $DryRun.IsPresent) {
    Write-Host "[PLANNING] Planungs-Lauf ($($GlobalState.planning_run_count)): Starte smarte Memory-Optimierung..." -ForegroundColor Yellow
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

        $partName = "PART-RUN-01_SR-05_MR-01_Planning__MemoryOptimization"
        $memResult = Invoke-PartRun `
            -PartRunName $partName `
            -AgentType "CEO" `
            -Prompt $promptText `
            -SubState $SubState `
            -Config $Config `
            -QuotaRegistry $QuotaRegistry `
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

# --- Optimizer Session ---
$optHours = if ($Config.wake_intervals.PSObject.Properties.Name -contains "optimizer_hours" -and $Config.wake_intervals.optimizer_hours) { [int]$Config.wake_intervals.optimizer_hours } else { 12 }
$runAnalysis = $false
$forceOptimizer = $false
if ((Test-ObjectProperty -Object $GlobalState -Name "run_control") -and (Test-ObjectProperty -Object $GlobalState.run_control -Name "force_optimizer") -and [bool]$GlobalState.run_control.force_optimizer) {
    $forceOptimizer = $true
    $runAnalysis = $true
}
if (-not ($GlobalState.PSObject.Properties.Name -contains "last_optimizer_analysis_at") -or [string]::IsNullOrWhiteSpace([string]$GlobalState.last_optimizer_analysis_at)) {
    $runAnalysis = $true
} elseif (-not $forceOptimizer) {
    try {
        $lastAt = [datetimeoffset]::Parse([string]$GlobalState.last_optimizer_analysis_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $ageHours = ((Get-Date) - $lastAt.LocalDateTime).TotalHours
        if ($ageHours -ge $optHours) {
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
        $stateJson = $GlobalState | ConvertTo-Json -Depth 15
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

        $partName = "PART-RUN-02_SR-05_MR-01_Planning__OptimizerAnalysis"
        $optResult = Invoke-PartRun `
            -PartRunName $partName `
            -AgentType "CEO" `
            -Prompt $promptText `
            -SubState $SubState `
            -Config $Config `
            -QuotaRegistry $QuotaRegistry `
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
                if (-not ($GlobalState.PSObject.Properties.Name -contains "optimizer_queue") -or $null -eq $GlobalState.optimizer_queue) {
                    $GlobalState | Add-Member -MemberType NoteProperty -Name "optimizer_queue" -Value @() -Force
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
                        $GlobalState.optimizer_queue += @($entry)
                        $proposalList += @($entry)
                        Write-Host "[OPTIMIZER] Neuer Optimierungsvorschlag hinzugefügt: $($p.title)" -ForegroundColor Green
                    }
                }

                $GlobalState.last_optimizer_analysis_at = (Get-Date -Format 'o')
                $nextOptimizerAt = (Get-Date).AddHours(12).ToString("o")
                $previousApproved = @()
                if ((Test-ObjectProperty -Object $GlobalState -Name "optimizer_last_run") -and $null -ne $GlobalState.optimizer_last_run -and (Test-ObjectProperty -Object $GlobalState.optimizer_last_run -Name "approved_changes")) {
                    $previousApproved = @($GlobalState.optimizer_last_run.approved_changes)
                }
                $GlobalState | Add-Member -MemberType NoteProperty -Name "optimizer_last_run" -Value ([pscustomobject]@{
                    ran_at = $GlobalState.last_optimizer_analysis_at
                    next_run_at = $nextOptimizerAt
                    forced = $forceOptimizer
                    proposals = @($proposalList)
                    approved_changes = @($previousApproved | Select-Object -Last 10)
                    summary = if ($proposalList.Count -gt 0) { "$($proposalList.Count) Optimierungsvorschlaege erzeugt." } else { "Keine neuen Optimierungsvorschlaege." }
                }) -Force
                if ($forceOptimizer -and $null -ne $GlobalState.run_control) {
                    $GlobalState.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer" -Value $false -Force
                    $GlobalState.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer_requested_at" -Value $null -Force
                }
                Save-AutopilotState -State $GlobalState
            } else {
                Write-Warning "[OPTIMIZER] Konnte Optimizer-Vorschläge nicht parsen oder keine Vorschläge generiert."
                if ($forceOptimizer -and $null -ne $GlobalState.run_control) {
                    $GlobalState.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer" -Value $false -Force
                }
            }
        }
    } catch {
        Write-Warning "Fehler bei Optimizer-Analyse: $_"
        if ($forceOptimizer -and $null -ne $GlobalState.run_control) {
            $GlobalState.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer" -Value $false -Force
        }
    }
}

$SubState.status = "completed"
