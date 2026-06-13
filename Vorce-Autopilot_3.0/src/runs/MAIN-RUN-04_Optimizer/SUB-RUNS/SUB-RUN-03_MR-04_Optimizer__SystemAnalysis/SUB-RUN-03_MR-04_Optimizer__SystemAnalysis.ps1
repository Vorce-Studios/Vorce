# src/runs/SUB-RUN/SUB-RUN-03_MR-04_Optimizer__SystemAnalysis.ps1
# Analysiert Logs, Quotas und Workflows auf Ineffizienzen und schlägt Optimierungen vor
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-03 SystemAnalysis: Generiere Optimizer-Vorschläge..." -ForegroundColor Cyan

$logContent = if ($MainState.PSObject.Properties.Name -contains "OptLogContent") { $MainState.OptLogContent } else { "" }
$ciCdContext = if ($MainState.PSObject.Properties.Name -contains "OptCiCdContext") { $MainState.OptCiCdContext } else { "" }
$forceOptimizer = if ($MainState.PSObject.Properties.Name -contains "ForceOptimizer") { $MainState.ForceOptimizer } else { $false }

$stateJson = $GlobalState | ConvertTo-Json -Depth 5 -Compress
$quotaJson = $QuotaRegistry | ConvertTo-Json -Depth 5 -Compress

Write-Host "[OPTIMIZER]   -> Starte PART-RUN: PerformanceReview" -ForegroundColor Cyan

$promptText = @"
Du bist der Vorce-Autopilot Optimizer-Agent.
Deine Aufgabe ist es, die internen Abläufe, System-Prompts, CI/CD-Pipelines, Repository-Einstellungen, den Tokenverbrauch und die Auslastung des Autopiloten zu analysieren und konkrete Optimierungsvorschläge zu erarbeiten.

Hier ist der aktuelle Status des Autopiloten (State):
$stateJson

Hier ist die Quota-Registry (Kosten und API-Aufrufe):
$quotaJson

Hier sind die letzten Zeilen der Live-Logdatei:
$logContent

Hier sind die aktuellen CI/CD Workflows (.github/workflows/):
$ciCdContext

Bitte analysiere diese Statistiken, Logs und Workflows auf Ineffizienzen, Fehlerraten, hohe Tokenkosten oder Automatisierungs-Engpässe.
Fokus auf:
- Autopilot Skripte & Prompts
- GitHub Actions CI/CD
- Repo Einstellungen & Workflow-Struktur

Schlage bis zu 3 konkrete Optimierungen vor. Jede Optimierung sollte einen klaren Titel, eine detaillierte Beschreibung des Problems, die erwartete Auswirkung (Impact) und die vorgeschlagene Aktion enthalten.

Gib deine Vorschläge AUSSCHLIESSLICH als JSON-Liste im folgenden Format zurück:
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

$partRun = Invoke-PartRun `
    -PartRunName "PART-RUN-01_SR-03_MR-04_Optimizer__PerformanceReview" `
    -AgentType "CEO" `
    -Prompt $promptText `
    -SubState $SubState `
    -Config $Config `
    -QuotaRegistry $QuotaRegistry `
    -DryRun:$DryRun

if ($partRun.success) {
    try {
        $proposals = $partRun.output | ConvertFrom-Json
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
                    if ($DryRun.IsPresent) {
                        Write-Host "[OPTIMIZER] [DRY RUN] Wuerde Optimierung vorschlagen: $($p.title)" -ForegroundColor Yellow
                    } else {
                        $GlobalState.optimizer_queue += @($entry)
                        $proposalList += @($entry)
                        Write-Host "[OPTIMIZER] Neuer Optimierungsvorschlag hinzugefügt: $($p.title)" -ForegroundColor Green
                    }
                }
            }

            if (-not $DryRun.IsPresent) {
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
            }
        }
    } catch {
        Write-Warning "[OPTIMIZER] Konnte Optimizer-Vorschläge nicht parsen."
        if ($forceOptimizer -and $null -ne $GlobalState.run_control) {
            $GlobalState.run_control | Add-Member -MemberType NoteProperty -Name "force_optimizer" -Value $false -Force
        }
    }
}

$SubState.status = "completed"
