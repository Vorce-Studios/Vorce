# VORCE-AUTOPILOT 2.0 – REFACTORING GUIDE

## Status der Migration (Stand 11.06.2026)

### [x] Phase 1: Infrastruktur
- Verzeichnisstruktur `src/orchestrator/`, `src/runs/MAIN-RUN/`, `src/runs/ROUTER/`, `src/runs/SUB-RUN/` angelegt.
- `run-state-manager.ps1` für hierarchisches State-Tracking implementiert.
- Doppelte/tote Ordner (`src/runs/main/`, `src/runs/sub/`, `src/runs/part/`, `src/router/`) entfernt.

### [x] Phase 2: Orchestrierung
- `Invoke-MainRun.ps1` (Orchestrator) mit Config-Fallback, Force-Modus und State-Aggregation implementiert.
- Router-Skripte config-basiert umgeschrieben (lesen aus `autopilot-config.json`).
- `autopilot.ps1` vollständig auf die neue Orchestrierung umgestellt (inkl. Single-Shot-Modi).
- `autopilot-config.json` korrigiert (Pfade auf `src/runs/SUB-RUN/`, explizite IDs).

### [x] Phase 3: Legacy-Migration (Fallback-Phase)
- Legacy-Fallbacks für Planning, Monitoring und Audit eingerichtet.
- SUB-RUN-01 Skripte (ContextGathering, SystemHealthCheck, ConsistencyAudit) implementiert.
- SUB-RUN-02 Skripte (LegacyFallback) rufen die alten Wakeup-Funktionen auf.

### [ ] Phase 4: Logik-Extraktion (Nächste Schritte)
- [ ] Logik aus `planning-wakeup.ps1` (56KB!) in dedizierte Sub-Runs extrahieren:
  - [ ] SUB-RUN für Goal-Evaluation
  - [ ] SUB-RUN für Task-Delegation (Jules Sessions)
  - [ ] SUB-RUN für PR-Check & Review-Delegation
- [ ] Logik aus `monitoring-wakeup.ps1` (55KB!) in Sub-Runs extrahieren:
  - [ ] SUB-RUN für Session-Status-Tracking
  - [ ] SUB-RUN für PR-Review & Merge
  - [ ] SUB-RUN für Escalation-Handling
- [ ] Logik aus `audit-wakeup.ps1` (11KB) in Sub-Runs extrahieren.
- [ ] Danach: Legacy-Fallback Sub-Runs in Config deaktivieren.
- [ ] Am Ende: `src/phases/` Dateien archivieren.

### [ ] Phase 5: Optimierung & Telemetrie
- [ ] Integration der Telemetrie-Werte in den Main-Run-State.
- [ ] Dashboard-Anbindung für hierarchische Run-States.
- [ ] Dynamische Router-Logik (z.B. "Keine Commits seit letztem Run → ContextGathering überspringen").
- [ ] Run-History Cleanup (alte `var/run/` Verzeichnisse nach X Tagen löschen).

---

## Anleitung: Neuen Sub-Run erstellen

1. Erstelle ein neues Skript in `src/runs/SUB-RUN/`:
   ```
   SUB-RUN-{NR}_MR-{MR-NR}_{Phase}__{Funktion}.ps1
   ```
   Beispiel: `SUB-RUN-03_MR-01_Planning__GoalEvaluation.ps1`

2. Verwende die Standard-Signatur:
   ```powershell
   param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
   ```

3. Registriere den Sub-Run in `config/autopilot-config.json`:
   ```json
   { "id": "03", "name": "GoalEvaluation", "script": "src/runs/SUB-RUN/SUB-RUN-03_MR-01_Planning__GoalEvaluation.ps1", "enabled": true }
   ```

4. Nutze `Add-RunArtifact` und `$SubState.artifacts` für Zwischenergebnisse.

5. **Kein Import von `Invoke-MainRun.ps1` nötig** – der Orchestrator übergibt automatisch alle States.

---

## Anleitung: Sub-Run deaktivieren

Setze `"enabled": false` in der Config. Der Router überspringt den Sub-Run, und der Orchestrator dokumentiert das Überspringen im `MAIN-RUN-STATE`.

## Anleitung: Alle Sub-Runs erzwingen

Rufe den Orchestrator mit `-ForceAllSubRuns` auf:
```powershell
Invoke-MainRun -MainRunName "MAIN-RUN-01_Planning" -GlobalState $State -Config $Config -ForceAllSubRuns
```
