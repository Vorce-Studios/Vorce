# src/runs/SUB-RUN/SUB-RUN-04_MR-03_Audit__AlertDisposition.ps1
# Generiert finale Dashboard-Alerts und vergleicht mit Memory (Spam-Verhinderung)
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-04 AlertDisposition: Generiere finale Dashboard-Alerts..." -ForegroundColor Cyan

$complianceAlerts = if ($MainState.PSObject.Properties.Name -contains "ComplianceAlerts") { @($MainState.ComplianceAlerts) } else { @() }
$julesAlerts = if ($MainState.PSObject.Properties.Name -contains "JulesAlerts") { @($MainState.JulesAlerts) } else { @() }

$allRawAlerts = @()
$allRawAlerts += $complianceAlerts
$allRawAlerts += $julesAlerts

if ($allRawAlerts.Count -eq 0) {
    Write-Host "[AUDIT] Keine Probleme von den vorherigen Part-Runs gemeldet. Audit sauber." -ForegroundColor Green
    $SubState.status = "completed"
    return
}

$rawAlertsJson = $allRawAlerts | ConvertTo-Json -Depth 3 -Compress

# Lade Memories (Ignorierte Alerts)
$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$memoryPath = Join-Path $ScriptDir "var/db/memory-store.json"
$memoriesJson = "[]"
if (Test-Path $memoryPath) {
    try {
        $memObj = Get-Content $memoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $ignoreMemories = @($memObj.memories | Where-Object { $_.text -match "IGNORE_ALERT" })
        if ($ignoreMemories.Count -gt 0) {
            $memoriesJson = $ignoreMemories | Select-Object id, text | ConvertTo-Json -Depth 3 -Compress
        }
    } catch { Write-Warning "[AUDIT] Memory-Store konnte nicht geladen werden." }
}

Write-Host "[AUDIT]   -> Starte PART-RUN: AlertSynthesis" -ForegroundColor Cyan

$synthesisPrompt = @"
Du bist der QA-MANAGER (Micro-Worker). Deine Aufgabe ist es, aus den rohen Problemberichten finale Dashboard-Alerts zu generieren.
WICHTIG: Du musst Spam verhindern! Vergleiche die Probleme mit den 'Ignorierten Alerts' aus dem Gedächtnis (Memories).
Wenn ein Problem exakt oder stark aehnlich einem ignorierten Alert ist, DARFST DU KEINEN ALERT generieren!

Rohe Probleme:
$rawAlertsJson

Ignorierte Alerts (Memories):
$memoriesJson

Erstelle eine finale JSON-Liste mit Eskalationen, die zwingend vom User im Dashboard bearbeitet werden muessen.
Format (JSON Array):
[
  {
    "topic": "Kurzer Titel",
    "context": "Hochdetaillierte Beschreibung was der User tun muss",
    "remediation_command": "Optional: Ein CLI Command (z.B. Git) zur Behebung. Darf nicht leer sein, falls vorhanden."
  }
]
Leeres Array ausgeben, wenn alle Probleme ignoriert wurden oder unkritisch sind.
"@

$partRun = Invoke-PartRun `
    -PartRunName "PART-RUN-01_SR-04_MR-03_Audit__AlertSynthesis" `
    -AgentType "QA-Manager" `
    -Prompt $synthesisPrompt `
    -SubState $SubState `
    -Config $Config `
    -QuotaRegistry $QuotaRegistry `
    -DryRun:$DryRun

if ($partRun.success) {
    try {
        $parsed = $partRun.output | ConvertFrom-Json
        if ($null -ne $parsed -and ($parsed -is [System.Array] -or $parsed -is [System.Collections.IList])) {
            foreach ($alert in $parsed) {
                if ($DryRun.IsPresent) {
                    Write-Host "[AUDIT] [DRY RUN] Wuerde Alert generieren: $($alert.topic)" -ForegroundColor Yellow
                } else {
                    $cmd = if ($alert.PSObject.Properties.Name -contains "remediation_command" -and -not [string]::IsNullOrWhiteSpace($alert.remediation_command)) { $alert.remediation_command } else { "" }
                    $remResult = ""
                    if ($cmd) {
                        Write-Host "[AUDIT] QA-Manager fuehrt Reparaturversuch aus: $cmd" -ForegroundColor Yellow
                        try {
                            $remOutput = Invoke-Expression $cmd 2>&1
                            $remResult = "Befehl erfolgreich ausgefuehrt:`n$remOutput"
                        } catch {
                            $remResult = "Fehler bei der Ausfuehrung:`n$_"
                        }
                    }
                    Add-DecisionPending -State $GlobalState -Topic $alert.topic -Context $alert.context -RemediationCommand $cmd -RemediationResult $remResult
                    Write-Host "[AUDIT] Neuer Alert zum Dashboard hinzugefuegt: $($alert.topic)" -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Warning "[AUDIT] Konnte JSON von AlertSynthesis nicht parsen."
    }
}

$SubState.status = "completed"
