# Vorce-Factory - Aktueller Code-Abgleich und Uebertragungsplan

Stand: 2026-06-19

Ziel dieses Plans: Die alten Plaene wurden gegen den aktuellen Code geprueft. Bereits erledigte Punkte werden nicht erneut geplant. Offene oder nur teilweise umgesetzte Punkte werden hier als aktueller Umsetzungsplan zusammengefuehrt.

## Gepruefte Bereiche

- PowerShell Backend: `autopilot.ps1`, `src/orchestrator/`, `src/lib/`, `src/runs/`
- Runtime-Daten: `var/config/`, `var/run-states/`, `var/prompts/`
- Dashboard: `web/Dashboard/vite.config.ts`, `web/Dashboard/src/**`
- Tests: `test/Test-Boot.ps1`, `test/Test-OrchestratorDryRun.ps1`, `test/Test-PlanningRun.ps1`, `test/Test-StartProcess.ps1`

## Bereits umgesetzt

- Die physische Run-Struktur existiert mit 5 MAIN-RUNs:
  `MAIN-RUN-01_Planning`, `MAIN-RUN-02_CheckAndDoing`, `MAIN-RUN-03_Audit`, `MAIN-RUN-04_Optimizer`, `MAIN-RUN-05_MemoryOptimization`.
- Alle konfigurierten SUB-RUNs besitzen mindestens einen PART-RUN-Ordner mit mindestens einer `.ps1`-Datei.
- `autopilot.ps1` setzt `$global:VorceRoot`, `$global:VarDir`, `$global:SrcDir`, `$global:LibDir`.
- `StateManager.ps1` nutzt `$global:VarDir` statt relativer `$PSScriptRoot`-Pfade.
- `ApiClient.ps1` enthaelt kein `Export-ModuleMember` mehr.
- `Vorce-Orchestrator.ps1` hat dynamische Main-Run-Auswahl, `-ForceMainRun`, ConfigBag, Router-Aufruf und Try/Catch je Sub-Run.
- `QuotaManager.ps1` existiert und prueft Provider, CLI-Kommandos, Tageslimit und Budget.
- `SettingsPage.tsx` nutzt `/run-catalog.json` fuer die Run-/Sub-/Part-Konfiguration.
- `npm run build` im Dashboard laeuft durch.
- `Test-Boot.ps1` und `Test-OrchestratorDryRun.ps1` bestehen.

## Muss aus alten Plaenen uebernommen werden

### P0 - Dashboard-Run-Hierarchie wirklich kanonisch bauen

Problem:
`web/Dashboard/src/pages/DashboardPage.tsx` erstellt die sichtbare `Run-Hierarchie` weiter aus `sessions.run_states`. `RunHierarchyView.tsx` rekonstruiert Eltern-Kind-Beziehungen aus Namen und scheitert bei Kurz-Namen, `unknown` und alten Runtime-Dateien. `/run-catalog.json` existiert, wird dort aber nicht fuer die Baumdarstellung verwendet.

Umsetzung:

- `/active-sessions.json` oder ein neuer Endpoint muss `run_hierarchy` liefern: 5 MAIN-RUNs -> SUB-RUNs -> PART-RUNs.
- Quelle: `var/config/autopilot-config.json`, `src/runs/**`, `var/run-states/*.json`.
- Jeder Sub-Run braucht `configured`, `router_active`, `executed`, `status`, `reason`, `last_state`.
- Jeder Part-Run muss unter seinem Sub-Run haengen, nicht als Root-Knoten.
- Alte Kurz-State-Dateien wie `SUB_DataSync.json`, `PART_FetchIssues.json`, `PART_FetchPRs.json` duerfen die Anzeige nicht dominieren.

Akzeptanz:

- Dashboard zeigt exakt 5 MAIN-RUNs als Root.
- Aktive und inaktive SUB-RUNs sind sichtbar.
- PART-RUNs erscheinen nur unter ihrem SUB-RUN.
- Keine `unknown`-Root-Knoten in der Run-Hierarchie.

### P0 - Router-Entscheidungen persistieren

Problem:
Router geben nur aktive Sub-Runs zurueck. Warum andere konfigurierte Sub-Runs inaktiv waren, wird nicht dauerhaft gespeichert. Dadurch kann das Dashboard nicht sauber visualisieren, welche Sub-Runs durch Routerlogik deaktiviert wurden.

Umsetzung:

- Router-Rueckgabe erweitern oder separaten `router_decision`-State schreiben.
- Pro konfiguriertem Sub-Run speichern:
  `sub_run`, `configured`, `config_enabled`, `router_active`, `reason`, `evidence`, `part_runs`.
- Orchestrator soll den Entscheidungs-Snapshot im MAIN-State speichern.

Akzeptanz:

- Nach jedem Main-Run ist nachvollziehbar, warum z.B. `Strategy`, `JulesCheck`, `ReviewDispatch` oder `AlertDisposition` aktiv/inaktiv war.

### P0 - Planning Strategy Argument-Passing reparieren

Problem:
`SUB-RUN-03_MR-01_Planning__Strategy.ps1` erstellt pro Issue einen Part-Run mit `arguments`. `Invoke-VorceSubRunParallel` uebergibt diese Argumente im Job aber nicht an den Part-Run. `CreateProposal.ps1` liest zudem `ConfigBag.Arguments`, obwohl die Argumente nicht dort gesetzt werden. Mehrere parallele Strategy-Parts koennen dadurch auf dasselbe erste Issue fallen.

Umsetzung:

- `RunEngine.ps1` muss `part.arguments` in den Job uebergeben.
- Entweder `CreateProposal.ps1` bekommt echte Parameter `IssueNumber`, `IssueTitle`, `IssueBody`, oder `RunEngine` injiziert sie kontrolliert in `ConfigBag.Arguments`.
- Tests muessen beweisen, dass drei triagierte Issues drei unterschiedliche Proposal-Dateien erzeugen.

### P0 - State-Namen normalisieren

Problem:
`SUB-RUN-01_MR-01_Planning__DataSync.ps1` nutzt Kurz-Namen:
`SubRunName = DataSync`, Parts `FetchIssues` und `FetchPRs`. Das erzeugt Runtime-Dateien wie `SUB_DataSync.json`, `PART_FetchIssues.json`, `PART_FetchPRs.json` und bricht die lange Run-Hierarchie.

Umsetzung:

- DataSync muss die langen Namen verwenden:
  `SUB-RUN-01_MR-01_Planning__DataSync`,
  `PART-RUN-01_MR-01_Planning__DataSync__FetchIssues`,
  `PART-RUN-02_MR-01_Planning__DataSync__FetchPRs`.
- Dashboard/API soll alte Kurz-State-Dateien entweder ignorieren oder als Legacy markieren.

### P0 - Logging-Modul und Live-Log reparieren

Problem:
`src/tools/services/sync-service.ps1` dot-sourced `src/lib/logging/Write-Log.ps1`, aber diese Datei definiert keine Funktion `Write-Log`; sie ist ein direkt ausfuehrbares Script mit Mandatory-Parametern. `StatusPrinter.ps1` schreibt nur ins Terminal. `/live-log.json` liest `var/log/autopilot-live.log`, aber `autopilot.ps1` schreibt `autopilot_yyyy-MM-dd_HH-mm.log`.

Umsetzung:

- `Write-Log.ps1` in ein echtes dot-sourcebares Modul mit Funktion `Write-Log` umbauen.
- `Write-VorceStep`, `Write-VorceRunStart`, `Write-VorceRunEnd` optional an `Write-Log` anbinden.
- Einheitliche Live-Log-Datei definieren, z.B. `var/log/autopilot-live.log`, mit Rotation fuer historische Logs.
- Sync-Service Start testen.

Akzeptanz:

- Terminal, Datei und Dashboard-Live-Log zeigen denselben Run-Fortschritt.
- `sync-service.ps1` startet ohne Mandatory-Parameter-Prompt und ohne `Write-Log`-Fehler.

### P0 - LLM/CLI-Fallback aus Registry implementieren

Problem:
`AgentRunner.ps1` kennt nur `gemini_cli` und `claude_code` direkt. Die Registry enthaelt aber `routing_rules` und Provider wie `codex_orchestrator`, `kiro_cli`, `copilot_cli`, `cursor_agent`, `cline_cli`. `DeliberationEngine.ps1` ruft dreimal hart `gemini_cli` auf.

Umsetzung:

- `Invoke-VorceAgentChain -TaskType <type>` implementieren.
- Chain aus `quota-registry.json.routing_rules` lesen.
- Provider-Kommandos aus `providers.<name>.command` und `cli_args` bauen.
- Bei ExitCode, leerem Output, Auth-/License-/Quota-Fehlern naechsten Provider versuchen.
- Fehlerklassifizierung speichern: `quota`, `auth`, `license`, `network`, `timeout`, `invalid_output`.

Akzeptanz:

- Deliberation nutzt `dual_ceo.ceo_chain` und `qa_manager_chain` oder Registry-Routing statt hartem Gemini.
- `Test-StartProcess.ps1` wird durch eine Provider-Smoke-Test-Suite ersetzt, die Fehler erfasst statt nur hart zu scheitern.

### P1 - MAIN-RUN-04 Optimizer fachlich ausbauen

Ist:
Optimizer sammelt Run-Zeiten, Quota-Daten und einfache Empfehlungen. Er schreibt Performance- und Analyse-JSON, nimmt aber keine restriktive, nachvollziehbare Optimierungsentscheidung vor.

Soll:

- Weitere Sub-Runs einfuehren oder bestehende erweitern:
  `MetricCollection`, `BottleneckAnalysis`, `OptimizationProposal`, `SafetyGate`, `FeedbackTracking`.
- Nur Vorschlaege erzeugen, wenn messbare Schwellen verletzt sind.
- Optimierbare Bereiche: Systemprompts, Run-Inhalte, Routerregeln, Split von Runs, Parallelitaet, Wake-Intervalle.
- Keine automatische Aenderung ohne Safety-Regel: kleine Config-Anpassungen duerfen optional staged werden, Code-/Prompt-Aenderungen als Proposal oder Issue.
- Optimizer-Entscheidungen in `var/analysis/optimizer-decisions.json` oder Dashboard-State schreiben.

Akzeptanz:

- Jede Empfehlung hat Metrik, Schwelle, erwartete Wirkung, Risiko und vorgeschlagenen Eingriff.
- Dashboard zeigt pending/approved/rejected Optimizer-Vorschlaege.

### P1 - MAIN-RUN-05 MemoryOptimization restriktiv und nutzungsbezogen machen

Ist:
MemoryMaintenance entfernt/archiviert/kuerzt Memories grob nach Alter, Laenge und Priority. Es gibt keine klare Auswahl, welche Memories in welchem Run wirklich in den Kontext duerfen.

Soll:

- Memory-Eintraege bekommen Felder: `scope`, `applies_to_runs`, `applies_to_issue`, `expires_at`, `last_used_at`, `use_count`, `token_cost_estimate`, `retention`.
- Vor Run-Ausfuehrung darf nur gezielt relevanter Kontext injiziert werden.
- Standard: keine Memory-Injektion, wenn kein konkreter Nutzen belegt ist.
- Master-Issue/Sub-Issue-Kontext: temporaere Memories mit Issue-Scope und Ablaufdatum, nutzbar fuer mehrere Agents/Sub-Issues.
- Pflegeaktionen: behalten, herabstufen, archivieren, loeschen, aber mit restriktiven Regeln und Audit-Bericht.

Akzeptanz:

- Pro Run ist sichtbar, welche Memory-Eintraege genutzt wurden und warum.
- Token-Budget fuer Memories ist begrenzt.
- Temporäre Master-Issue-Memories laufen automatisch aus.

### P1 - Produktname vollstaendig auf Vorce-Factory umstellen

Problem:
Aktive Code- und Prompt-Treffer enthalten weiterhin `Vorce Autopilot` / `Vorce-Autopilot`, z.B. Dashboard-Titel, Footer, `autopilot.ps1` Header, Prompt-Rollen und Issue-Bodies.

Umsetzung:

- Sichtbare Produktnamen auf `Vorce-Factory` aendern.
- Technische Dateinamen wie `autopilot.ps1` nur aendern, wenn Aufrufer/Tests mitgezogen werden.
- Historische Dokumente duerfen alte Namen nur mit Hinweis `historisch` enthalten.

### P1 - Tests aktualisieren

Problem:
`Test-PlanningRun.ps1` prueft noch auf `*Vorce-Autopilot_NEW` und faellt deshalb fehl. `Test-StartProcess.ps1` hat hardcodierte lokale Pfade und testet nur Gemini direkt.

Umsetzung:

- `Test-PlanningRun.ps1` auf `Vorce-Factory` aktualisieren.
- Neue Tests fuer:
  - kanonische Run-Hierarchie aus Config + Ordnern,
  - Router-Decision-State,
  - Strategy Argument-Passing,
  - DataSync Long-State-Namen,
  - Logging-Modul dot-sourcebar,
  - Provider-Fallback-Kette.

### P2 - Prompt-Registry vervollstaendigen

Problem:
Prompt-Registry enthaelt keine spezifischen Prompt-Eintraege fuer MAIN-RUN-04 und MAIN-RUN-05. Settings kann daher fuer diese Bereiche keine echten fachlichen Prompts aus der Registry anzeigen.

Umsetzung:

- Prompts fuer Optimizer und MemoryOptimization erstellen und registrieren.
- Alte `Vorce Autopilot` Rollenformulierungen in aktiven Prompts auf `Vorce-Factory` aendern.

## Verifikation

Bereits ausgefuehrt:

- `npm run build` in `web/Dashboard`: erfolgreich, mit Bundle-Groessenwarnung.
- `powershell -File test/Test-Boot.ps1`: 61/61 bestanden.
- `powershell -File test/Test-OrchestratorDryRun.ps1`: 16/16 bestanden.
- `powershell -File test/Test-PlanningRun.ps1`: 25/26 bestanden; Fehlcheck ist alter Root-Name.
- `powershell -File test/Test-StartProcess.ps1`: fehlgeschlagen durch Gemini CLI Auth/License/Netzwerkfehler; Fallback-Smoke-Test fehlt.

## Reihenfolge

1. Dashboard-Hierarchie + Router-Decision-State + Long-State-Namen fixen.
2. Strategy Argument-Passing reparieren und testen.
3. Logging/Live-Log/Sync-Service stabilisieren.
4. LLM Provider-Fallback und CLI-Smoke-Tests implementieren.
5. MAIN-RUN-04 und MAIN-RUN-05 fachlich erweitern.
6. Rename-Reste und Prompt-Registry bereinigen.
