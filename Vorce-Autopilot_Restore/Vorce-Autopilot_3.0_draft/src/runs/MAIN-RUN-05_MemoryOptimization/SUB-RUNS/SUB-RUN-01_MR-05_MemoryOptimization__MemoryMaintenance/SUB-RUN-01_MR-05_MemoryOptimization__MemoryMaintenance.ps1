# src/runs/SUB-RUN/SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1
# Pflegt den MemoryStore des Autopiloten
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-02 MemoryMaintenance: Optimiere System-Memory..." -ForegroundColor Cyan

$memoriesJson = if ($MainState.PSObject.Properties.Name -contains "OptMemStoreJson") { $MainState.OptMemStoreJson } else { "{}" }
$journalContent = if ($MainState.PSObject.Properties.Name -contains "OptJournalContent") { $MainState.OptJournalContent } else { "" }

Write-Host "[OPTIMIZER]   -> Starte PART-RUN: MemoryEvaluation" -ForegroundColor Cyan

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

Gib deine Entscheidung AUSSCHLIESSLICH als JSON-Liste von Aktionen im folgenden Format zurück:
[
  { "action": "remove", "id": "mem-id-here" },
  { "action": "add", "text": "Erinnerungstext hier", "type": "permanent|temporary", "priority": "critical|high|medium" }
]

Wenn keine Änderungen notwendig sind, antworte mit einem leeren Array: []
"@

$partRun = Invoke-PartRun `
    -PartRunName "PART-RUN-01_SR-02_MR-04_Optimizer__MemoryEvaluation" `
    -AgentType "CEO" `
    -Prompt $promptText `
    -SubState $SubState `
    -Config $Config `
    -QuotaRegistry $QuotaRegistry `
    -DryRun:$DryRun

if ($partRun.success) {
    try {
        $actions = $partRun.output | ConvertFrom-Json
        if ($null -ne $actions -and ($actions -is [System.Array] -or $actions -is [System.Collections.IList])) {
            foreach ($act in $actions) {
                if ($act.action -eq "remove" -and $act.id) {
                    if ($DryRun.IsPresent) {
                        Write-Host "[OPTIMIZER] [DRY RUN] Wuerde Memory entfernen: $($act.id)" -ForegroundColor Yellow
                    } else {
                        Write-Host "[OPTIMIZER] Smart Memory: Entferne Erinnerung $($act.id)" -ForegroundColor Yellow
                        Remove-Memory -Id $act.id
                    }
                } elseif ($act.action -eq "add" -and $act.text) {
                    if ($DryRun.IsPresent) {
                        Write-Host "[OPTIMIZER] [DRY RUN] Wuerde Memory hinzufuegen: $($act.text)" -ForegroundColor Green
                    } else {
                        Write-Host "[OPTIMIZER] Smart Memory: Fuege Erinnerung hinzu: $($act.text)" -ForegroundColor Green
                        $priority = if ($act.priority) { $act.priority } else { "medium" }
                        $type = if ($act.type) { $act.type } else { "temporary" }
                        Add-Memory -Text $act.text -Type $type -Priority $priority -Source "autopilot_smart_memory"
                    }
                }
            }
        }
    } catch {
        Write-Warning "[OPTIMIZER] Konnte JSON von MemoryEvaluation nicht parsen."
    }
} else {
    Write-Warning "[OPTIMIZER] MemoryEvaluation fehlgeschlagen: $($partRun.error)"
    $SubState.status = "failed"
}

$SubState.completed_at = (Get-Date).ToString('o')
