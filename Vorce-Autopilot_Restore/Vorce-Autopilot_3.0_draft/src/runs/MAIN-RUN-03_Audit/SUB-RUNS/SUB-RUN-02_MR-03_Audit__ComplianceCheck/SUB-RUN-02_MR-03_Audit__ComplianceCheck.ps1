# src/runs/SUB-RUN/SUB-RUN-02_MR-03_Audit__ComplianceCheck.ps1
# Prueft Issues und PRs auf Namenskonventionen und Konsistenz
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-02 ComplianceCheck: Evaluiere Issue/PR-Compliance..." -ForegroundColor Cyan

$issuesData = if ($MainState.PSObject.Properties.Name -contains "AuditIssuesData") { $MainState.AuditIssuesData } else { "" }
$prsData = if ($MainState.PSObject.Properties.Name -contains "AuditPrsData") { $MainState.AuditPrsData } else { "" }

$complianceAlerts = @()

# --- 1. PART-RUN: IssueCompliance ---
if (-not [string]::IsNullOrWhiteSpace($issuesData)) {
    Write-Host "[AUDIT]   -> Starte PART-RUN: IssueCompliance" -ForegroundColor Cyan

    $issuePrompt = @"
Du bist der QA-MANAGER (Micro-Worker). Deine Aufgabe ist es, offene Issues auf Einhaltung der Namenskonventionen zu pruefen.
Konventionen:
- Standard-Issue: `*D**-000_Task-Title` (wobei 000 Ziffern sind)
- Master-Issue: `M...-000_Task-Title`
- Sub-Issue: `___M-{ParentMasterID}_s{SubIndex}_Task-Title`
- VERBOTEN sind: VOR-, __VOR-, MF-StIs_

Hier sind die aktuellen offenen Issues:
$issuesData

Pruefe, ob es Issues gibt, die gegen diese Namenskonventionen verstossen.
Falls ja, gib fuer jedes Problem eine Warnung zurueck.
Antworte zwingend als JSON in folgendem Format (Wenn keine Probleme gefunden wurden, leeres Array):
[
  { "topic": "Issue #123 verletzt Namenskonvention", "context": "Titel 'VOR-123_Test' ist veraltet. Muss zu *D**-123_Test werden." }
]
"@

    $partRun1 = Invoke-PartRun `
        -PartRunName "PART-RUN-01_SR-02_MR-03_Audit__IssueCompliance" `
        -AgentType "QA-Manager" `
        -Prompt $issuePrompt `
        -SubState $SubState `
        -Config $Config `
        -QuotaRegistry $QuotaRegistry `
        -DryRun:$DryRun

    if ($partRun1.success) {
        try {
            $parsed = $partRun1.output | ConvertFrom-Json
            if ($null -ne $parsed -and ($parsed -is [System.Array] -or $parsed -is [System.Collections.IList])) {
                $complianceAlerts += @($parsed)
                Write-Host "[AUDIT]      IssueCompliance abgeschlossen: $($parsed.Count) Probleme gefunden." -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning "[AUDIT] Konnte JSON von IssueCompliance nicht parsen."
        }
    }
} else {
    Write-Host "[AUDIT]   -> Ueberspringe IssueCompliance (Keine offenen Issues)." -ForegroundColor DarkGray
}

# --- 2. PART-RUN: PrCompliance ---
if (-not [string]::IsNullOrWhiteSpace($prsData)) {
    Write-Host "[AUDIT]   -> Starte PART-RUN: PrCompliance" -ForegroundColor Cyan

    $prPrompt = @"
Du bist der QA-MANAGER (Micro-Worker). Deine Aufgabe ist es, offene Pull Requests zu ueberpruefen.
Pruefe Folgendes:
1. Hat der PR Merge-Konflikte (mergeable: CONFLICTING)?
2. Fehlen dem PR saubere Bezeichnungen (sollte Issue-Nummer im Titel haben)?

Hier sind die offenen PRs:
$prsData

WICHTIGE REGEL:
Erstelle NIEMALS 'remediate_command' oder Loesungsvorschlaege zum automatischen Beheben von Merge-Konflikten via Jules! Das Loesen von Konflikten ist Planning-Sache. Du meldest nur die Fakten fuer das Dashboard.

Antworte zwingend als JSON in folgendem Format (Wenn keine Probleme gefunden wurden, leeres Array):
[
  { "topic": "PR #456 hat Merge-Konflikte", "context": "Der PR 'Fix UI' ist CONFLICTING und muss vom User oder im Planning geprueft werden." }
]
"@

    $partRun2 = Invoke-PartRun `
        -PartRunName "PART-RUN-02_SR-02_MR-03_Audit__PrCompliance" `
        -AgentType "QA-Manager" `
        -Prompt $prPrompt `
        -SubState $SubState `
        -Config $Config `
        -QuotaRegistry $QuotaRegistry `
        -DryRun:$DryRun

    if ($partRun2.success) {
        try {
            $parsed = $partRun2.output | ConvertFrom-Json
            if ($null -ne $parsed -and ($parsed -is [System.Array] -or $parsed -is [System.Collections.IList])) {
                $complianceAlerts += @($parsed)
                Write-Host "[AUDIT]      PrCompliance abgeschlossen: $($parsed.Count) Probleme gefunden." -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning "[AUDIT] Konnte JSON von PrCompliance nicht parsen."
        }
    }
} else {
    Write-Host "[AUDIT]   -> Ueberspringe PrCompliance (Keine offenen PRs)." -ForegroundColor DarkGray
}

$MainState | Add-Member -MemberType NoteProperty -Name "ComplianceAlerts" -Value $complianceAlerts -Force
$SubState.status = "completed"
