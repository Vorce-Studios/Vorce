# src/runs/SUB-RUN/SUB-RUN-03_MR-03_Audit__JulesSupervision.ps1
# Analysiert hängende/gescheiterte Jules-Sessions
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-03 JulesSupervision: Evaluiere Jules-Sessions..." -ForegroundColor Cyan

$delegationsData = if ($MainState.PSObject.Properties.Name -contains "AuditDelegationsData") { $MainState.AuditDelegationsData } else { "" }

$julesAlerts = @()

if (-not [string]::IsNullOrWhiteSpace($delegationsData)) {
    Write-Host "[AUDIT]   -> Starte PART-RUN: SessionAnalysis" -ForegroundColor Cyan

    $sessionPrompt = @"
Du bist der QA-MANAGER (Micro-Worker). Deine Aufgabe ist es, Jules-Agent-Sessions zu ueberwachen.
Hier sind die aktuellen Delegierungen:
$delegationsData

WICHTIGE REGELN FUER JULES-SESSIONS:
1. Wenn eine Session den Status 'AWAITING_USER_FEEDBACK' oder 'FAILED' hat, benoetigt sie Aufmerksamkeit.
2. STRENGES VERBOT FÜR JULES-CANCEL: Du darfst NIEMALS Aktionen vorschlagen, die eine Jules-Session abbrechen, stoppen oder löschen!
3. Wenn ein PR-Konflikt vorliegt, wird das im Planning geloest. Hier im Audit dokumentierst du es nur als Alert fuer das Dashboard.

Antworte zwingend als JSON in folgendem Format (Wenn keine Probleme gefunden wurden, leeres Array):
[
  { "topic": "Jules Session #745 braucht Hilfe", "context": "Die Session wartet auf User-Feedback. Bitte im Dashboard den Status pruefen und Jules eine Antwort geben." }
]
"@

    $partRun = Invoke-PartRun `
        -PartRunName "PART-RUN-01_SR-03_MR-03_Audit__SessionAnalysis" `
        -AgentType "QA-Manager" `
        -Prompt $sessionPrompt `
        -SubState $SubState `
        -Config $Config `
        -QuotaRegistry $QuotaRegistry `
        -DryRun:$DryRun

    if ($partRun.success) {
        try {
            $parsed = $partRun.output | ConvertFrom-Json
            if ($null -ne $parsed -and ($parsed -is [System.Array] -or $parsed -is [System.Collections.IList])) {
                $julesAlerts += @($parsed)
                Write-Host "[AUDIT]      SessionAnalysis abgeschlossen: $($parsed.Count) Alerts generiert." -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning "[AUDIT] Konnte JSON von SessionAnalysis nicht parsen."
        }
    }
} else {
    Write-Host "[AUDIT]   -> Ueberspringe SessionAnalysis (Keine Delegierungen)." -ForegroundColor DarkGray
}

$MainState | Add-Member -MemberType NoteProperty -Name "JulesAlerts" -Value $julesAlerts -Force
$SubState.status = "completed"
