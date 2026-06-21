# Vorce-Factory - Historischer Rebuild Status

> Historisch: Dieser Status ist durch den aktuellen Code teilweise ueberholt. Aktuelle offene Punkte stehen in `CURRENT_IMPLEMENTATION_GAP_PLAN.md`.

> **Stand:** 2026-06-14 | Legende: 🟢 Vollständig & getestet · 🟡 Stub/unvollständig · 🔴 Kritischer Bug · ⚪ Fehlt

---

## 1. Infrastruktur & Boot

| Status | Datei | Anmerkung |
|--------|-------|-----------|
| 🟡 | `autopilot.ps1` | Basis-Loop vorhanden; setzt `$global:VorceRoot` noch **nicht** → C1 |
| 🟡 | `Start-Autopilot.ps1` | Dashboard-Start OK; `$ToolsDir` referenziert `src/tools/` das nicht existiert |

---

## 2. Kern-Bibliotheken (`src/lib/`)

| Status | Datei | Anmerkung |
|--------|-------|-----------|
| 🟢 | `StatusPrinter.ps1` | Vollständig, funktioniert |
| 🔴 | `StateManager.ps1` | Pfad-Bug: `$PSScriptRoot` relativ → falsch aus Job-Kontext (C1) |
| 🔴 | `ApiClient.ps1` | `Export-ModuleMember` in Dot-Source-Datei → wirft Error (C3) |
| 🟢 | `GitHubClient.ps1` | Issues & PRs abrufbar, Pfad via `$PSScriptRoot` (C1 gilt auch hier) |
| 🟡 | `ProjectManager.ps1` | Stub: findet Projekt, aber editiert kein Item |
| 🟡 | `AgentRunner.ps1` | Gemini & Claude implementiert; enthält DEBUG-Zeilen; kein Quota-Check vor Aufruf |
| 🟢 | `PromptManager.ps1` | Template-Ersetzung funktioniert; Fallback-Pfade korrekt |
| 🔴 | `RunEngine.ps1` | Job-Kontext-Bug: `$VarDir` im Background-Job nicht verfügbar (C2) |
| 🟡 | `DeliberationEngine.ps1` | Logik korrekt; nutzt aber `AgentRunner` ohne Quota-Prüfung |
| 🟢 | `TriageUtils.ps1` | Filter-Logik vollständig |
| ⚪ | `QuotaManager.ps1` | **Fehlt komplett** — in REBUILD_STATUS fälschlicherweise als vorhanden markiert (L1) |

---

## 3. Orchestrierung (`src/orchestrator/`)

| Status | Datei | Anmerkung |
|--------|-------|-----------|
| 🔴 | `Vorce-Orchestrator.ps1` | Hardkodiert auf `MAIN-RUN-01_Planning`; keine Scheduling-Logik; kein Error-Handling für Sub-Run-Fehler (C4, L9) |

---

## 4. Runs (`src/runs/`)

### MAIN-RUN-01_Planning

| Status | Datei | Anmerkung |
|--------|-------|-----------|
| 🟡 | `Planning-Router.ps1` | Reiner Stub — gibt immer dieselben 3 Sub-Runs zurück (L10) |
| 🔴 | `SUB-RUN-01_DataSync.ps1` | Fehlt `GitHubClient.ps1`-Import; Pfad-Bug durch C1 |
| 🟡 | `SUB-RUN-02_Triage.ps1` | Stub — ruft keine echte Triage-Logik auf |
| 🟡 | `SUB-RUN-03_Strategy.ps1` | Stub — ruft keine echte Deliberation auf |
| ⚪ | `SUB-RUN-04_Delegation.ps1` | **Fehlt** — in Config definiert, Skript nicht vorhanden (L4) |
| 🟢 | `PART-RUN-01_FetchIssues.ps1` | Funktionsfähig |
| 🟢 | `PART-RUN-02_FetchPRs.ps1` | Funktionsfähig |
| 🟢 | `PART-RUN-03_FilterIssues.ps1` | Vollständig |
| 🟡 | `PART-RUN-04_CreateProposal.ps1` | Hardkodierte Strings (C6); keine Config-Lesing |

### MAIN-RUN-02_CheckAndDoing

| Status | Datei | Anmerkung |
|--------|-------|-----------|
| ⚪ | `CheckAndDoing-Router.ps1` | **Fehlt** (L5) |
| ⚪ | `SUB-RUN-01_SessionSync.ps1` | **Fehlt** (L5) |
| ⚪ | `SUB-RUN-02_JulesCheck.ps1` | **Fehlt** (L5) |
| ⚪ | `SUB-RUN-03_LocalAgentCheck.ps1` | **Fehlt** (L5) |
| ⚪ | `SUB-RUN-04_ReviewDispatch.ps1` | **Fehlt** (L5) |

### MAIN-RUN-03_Audit

| Status | Datei | Anmerkung |
|--------|-------|-----------|
| ⚪ | Gesamtes Verzeichnis | **Fehlt** (L6, niedrige Priorität) |

---

## 5. Tests (`test/`)

| Status | Datei | Anmerkung |
|--------|-------|-----------|
| ⚪ | `Test-Boot.ps1` | **Fehlt** — Checkpoint 1 ungetestet (L7) |
| ⚪ | `Test-OrchestratorDryRun.ps1` | **Fehlt** — Checkpoint 2 ungetestet (L7) |
| 🟡 | `Test-StartProcess.ps1` | Vorhanden, Umfang unklar |

---

## 6. Daten & Konfiguration (`var/`)

| Status | Pfad | Anmerkung |
|--------|------|-----------|
| 🟢 | `var/config/autopilot-config.json` | Vollständig; referenziert `kiro_cli` der nicht implementiert ist |
| 🟢 | `var/config/quota-registry.json` | Vorhanden |
| 🟢 | `var/db/*.json` | Alle DB-Dateien vorhanden |
| ⚪ | `var/db/proposals/` | **Verzeichnis fehlt** — wird von `CreateProposal` erwartet (L3) |
| ⚪ | `var/log/` | **Verzeichnis fehlt** — Rolling Logs können nicht geschrieben werden (L2) |
| 🟢 | `var/prompts/` | Alle Prompt-MD-Dateien vorhanden |
| 🟢 | `var/run-states/` | Vorhanden |

---

## 7. Dashboard (`web/Dashboard/`)

| Status | Komponente | Anmerkung |
|--------|-----------|-----------|
| 🟡 | Vite Dev-Setup | Läuft, muss auf `var/db/` zeigen |
| ⚪ | Echtzeit-Sync | **Fehlt** — falsch als vite.config-Feature beschrieben; muss als Polling in React implementiert werden (D4) |

---

## Nächste Schritte (Priorität)

1. 🔴 **[C1]** `$global:VorceRoot` Pattern in `autopilot.ps1` einführen + alle Module umstellen
2. 🔴 **[C2]** `RunEngine.ps1` Job-Pfade fixen
3. 🔴 **[C3]** `ApiClient.ps1` `Export-ModuleMember` entfernen
4. 🔴 **[C4]** Orchestrator Scheduling-Logik implementieren
5. ⚪ **[L1]** `QuotaManager.ps1` implementieren
6. ⚪ **[L4]** `SUB-RUN-04_Delegation.ps1` implementieren
7. ⚪ **[L5]** Alle MAIN-RUN-02 Dateien implementieren
8. ⚪ **[L7]** Test-Skripte schreiben
