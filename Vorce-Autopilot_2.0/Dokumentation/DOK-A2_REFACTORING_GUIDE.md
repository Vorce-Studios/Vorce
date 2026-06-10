# VORCE-AUTOPILOT 2.0 - REFACTORING GUIDE (WIP)

## Status der Migration (Stand 10.06.2026)

### [x] Phase 1: Infrastruktur
- Verzeichnisstruktur `src/orchestrator`, `src/router`, `src/runs` angelegt.
- `run-state-manager.ps1` für hierarchisches Tracking implementiert.

### [x] Phase 2: Orchestrierung
- `Invoke-MainRun.ps1` (Orchestrator) implementiert.
- `Invoke-MainRunRouter.ps1` (Router) mit Fallback-Logik implementiert.
- `autopilot.ps1` auf die neue Orchestrierung umgestellt.

### [/] Phase 3: Logik-Migration (In Arbeit)
- [x] Legacy-Fallbacks für Planning, Monitoring und Audit eingerichtet.
- [ ] Extraktion der Logik aus `planning-wakeup.ps1` in Sub-Runs.
- [ ] Extraktion der Logik aus `monitoring-wakeup.ps1` in Sub-Runs.

### [ ] Phase 4: Optimierung & Statistik
- [ ] Integration der Telemetrie-Werte in den Main-Run-State.
- [ ] Dashboard-Anbindung für hierarchische Run-States.

## Anleitung zur Logik-Migration
Um einen Teil der alten Logik (z.B. den PR-Check) zu migrieren:
1. Erstelle ein neues Skript in `src/runs/sub/SR-XX_Name.ps1`.
2. Kopiere die Logik aus dem alten Wakeup-Skript.
3. Nutze `Add-RunArtifact`, um wichtige Zwischenergebnisse im Run-State zu speichern.
4. Registriere den neuen Sub-Run im `Invoke-MainRunRouter.ps1`.
