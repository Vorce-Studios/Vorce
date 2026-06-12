# DOK-A4: SUB-RUN Entwicklung (für AI-Agenten)

Dieses Dokument definiert die Schnittstelle und Struktur für die Entwicklung neuer `SUB-RUN` Skripte im Vorce-Autopilot 2.0.

## 1. Skript-Signatur

Jeder Sub-Run muss exakt diese Parameter-Struktur akzeptieren:

```powershell
param(
    [Parameter(Mandatory)][object]$MainState,    # State des aktuellen Main-Runs
    [Parameter(Mandatory)][object]$SubState,     # Eigener State dieses Sub-Runs
    [Parameter(Mandatory)][object]$GlobalState,  # Systemweiter State (ReadOnly bevorzugt)
    [Parameter(Mandatory)][object]$Config,       # Gesamte autopilot-config.json
    [Parameter(Mandatory)][object]$QuotaRegistry,# Aktuelle Quoten-Daten
    [switch]$DryRun                              # Simulations-Modus
)
```

## 2. State-Verantwortlichkeiten

### MainState
Dient zum Datenaustausch zwischen Sub-Runs innerhalb derselben Phase.
- **Lesen:** Daten von vorherigen Sub-Runs abrufen.
- **Schreiben:** Ergebnisse für nachfolgende Sub-Runs bereitstellen (z.B. `$MainState.PlanningCandidates`).

### SubState
Protokolliert die Ausführung des spezifischen Sub-Runs.
- **status:** Muss am Ende auf `"completed"` gesetzt werden.
- **artifacts:** Hier sollten wichtige Zwischenergebnisse (Hashtables/JSON) abgelegt werden.
- **errors:** Fehler mit `Add-RunError` hinzufügen (setzt den Status automatisch auf `"failed"`).

## 3. Best Practices für Agenten

- **Surgische Logik:** Ein Sub-Run sollte genau eine Aufgabe erfüllen (z.B. nur Daten holen oder nur Triage durchführen).
- **Keine direkten GlobalState Änderungen:** Änderungen am `GlobalState` sollten nur über die dafür vorgesehenen Funktionen in `state-manager.ps1` erfolgen.
- **Logging:** Nutze `Write-Host` mit Farben für den Orchestrator-Output (Cyan für Start, Green für Erfolg, Red für Fehler).
- **Fehlerbehandlung:** Nutze `try/catch` Blöcke, um Abstürze zu verhindern und Fehler im `SubState` zu protokollieren.

## 4. Beispiel-Struktur

```powershell
# Beispiel: SUB-RUN-01_SimpleTask.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "[SUB-RUN] Starte Beispiel-Task..." -ForegroundColor Cyan

try {
    # 1. Logik ausführen
    $data = Get-Something -Repo $Config.repository

    # 2. Ergebnisse für Main-Run speichern
    $MainState.ResultData = $data

    # 3. Abschluss dokumentieren
    $SubState.status = "completed"
    $SubState.artifacts += @{ type = "Report"; count = $data.Count }
} catch {
    # Fehler protokollieren
    . (Join-Path $PSScriptRoot "../../lib/run-state-manager.ps1")
    Add-RunError -State $SubState -Message "Task fehlgeschlagen: $_"
}
```

---
*Vorce-Autopilot 2.0 - Technische Spezifikation für Agenten*
