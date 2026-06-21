# Agent-Prompts fuer Run-Hierarchie, Audit, Rename und Logik-Validierung

Stand: 2026-06-21

Arbeitskontext fuer alle Agents:

- Repo-Root: `C:\Users\Vinyl\Desktop\VJMapper\VJMapper`
- Hauptsystem: `Vorce-Factory/`
- Dashboard: `Vorce-Factory/web/Dashboard/`
- Wichtige Doku: `Vorce-Factory/docs/Documentations/DOCUMENTATION.md`, `Vorce-Factory/docs/Documentations/Agent-Doku.md`, `Vorce-Factory/docs/Documentations/README.md`
- Wichtig: Das Worktree kann bereits User-/Runtime-Aenderungen enthalten. Keine fremden Aenderungen revertieren. Keine `node_modules/`-Aenderungen anfassen. `dist/` nur aktualisieren, wenn ein Build bewusst Teil des Auftrags ist.

Soll-Run-Struktur laut Doku und aktueller Ordnerstruktur:

```text
MAIN-RUN-01_Planning
  SUB-RUN-01_MR-01_Planning__DataSync
    PART-RUN-01_MR-01_Planning__DataSync__FetchIssues
    PART-RUN-02_MR-01_Planning__DataSync__FetchPRs
  SUB-RUN-02_MR-01_Planning__Triage
    PART-RUN-01_MR-01_Planning__Triage__FilterIssues
  SUB-RUN-03_MR-01_Planning__Strategy
    PART-RUN-01_MR-01_Planning__Strategy__CreateProposal
  SUB-RUN-04_MR-01_Planning__Delegation
    PART-RUN-01_MR-01_Planning__Delegation__CreateDelegations

MAIN-RUN-02_CheckAndDoing
  SUB-RUN-01_MR-02_CheckAndDoing__SessionSync
    PART-RUN-01_MR-02_CheckAndDoing__SessionSync__SyncActiveSessions
  SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck
    PART-RUN-01_MR-02_CheckAndDoing__JulesCheck__InspectJulesSessions
  SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck
    PART-RUN-01_MR-02_CheckAndDoing__LocalAgentCheck__InspectLocalAgents
  SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch
    PART-RUN-01_MR-02_CheckAndDoing__ReviewDispatch__DispatchReviews
  SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill
    PART-RUN-01_MR-02_CheckAndDoing__JulesRefill__RefillJulesQueue
  SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping
    PART-RUN-01_MR-02_CheckAndDoing__Housekeeping__CleanupRuntimeState

MAIN-RUN-03_Audit
  SUB-RUN-01_MR-03_Audit__DataSync
    PART-RUN-01_MR-03_Audit__DataSync__ValidateDataSources
  SUB-RUN-02_MR-03_Audit__ComplianceCheck
    PART-RUN-01_MR-03_Audit__ComplianceCheck__EvaluateCompliance
  SUB-RUN-03_MR-03_Audit__JulesSupervision
    PART-RUN-01_MR-03_Audit__JulesSupervision__SuperviseJulesSessions
  SUB-RUN-04_MR-03_Audit__AlertDisposition
    PART-RUN-01_MR-03_Audit__AlertDisposition__DispositionAlerts

MAIN-RUN-04_Optimizer
  SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection
    PART-RUN-01_MR-04_Optimizer__PerformanceDataCollection__CollectPerformanceMetrics
  SUB-RUN-02_MR-04_Optimizer__SystemAnalysis
    PART-RUN-01_MR-04_Optimizer__SystemAnalysis__AnalyzeSystemPerformance

MAIN-RUN-05_MemoryOptimization
  SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance
    PART-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance__OptimizeMemoryStore
```

## Verifizierter Implementierungsstand bis einschliesslich Punkt 4A

Pruefdatum: 2026-06-21

Wichtig: Gruene Einzeltests bedeuten nicht, dass ein Prompt vollstaendig umgesetzt ist.

Statuslegende:

- `[ERLEDIGT]`: Alle Aufgaben und Akzeptanzkriterien des Prompts sind nachweislich umgesetzt und getestet.
- `[TEILWEISE]`: Verwendbare Teile sind vorhanden, aber mindestens ein Pflichtbestandteil oder Akzeptanztest fehlt.
- `[OFFEN]`: Der zentrale geforderte Funktionsumfang fehlt oder ist noch nicht nutzbar.

Gesamtentscheidung:

- **Keiner der Punkte 1A bis 4A ist aktuell als vollstaendig `[ERLEDIGT]` verifiziert.**
- **Die Implementierung ist daher nicht erfolgreich bis einschliesslich 4A abgeschlossen.**
- Vorhandene Teilergebnisse duerfen weiterverwendet werden, ersetzen aber nicht die unten genannten offenen Arbeiten.

| Punkt | Status | Bereits erledigt/vorhanden | Noch offen bis zur Abnahme |
|---|---|---|---|
| 1A | `[TEILWEISE]` | `getRunHierarchy()` und `/run-hierarchy.json` existieren in `web/Dashboard/vite.config.ts`. Die API erzeugt die 5 erwarteten MAIN-RUN-Wurzeln und liest Config, Ordnerstruktur und Run-States. | Legacy-Erkennung korrigieren, damit kanonische `PART_PART-RUN-*` States nicht als Orphans gelten. Datenvertrag in `types.ts` definieren. API-/Fixture-Test fuer exakt 5/17/18 Knoten und Legacy-Orphans ergaenzen. |
| 1B | `[TEILWEISE, AKTUELL NICHT FUNKTIONSFAEHIG]` | `App.tsx` laedt `/run-hierarchy.json`. `DashboardPage.tsx` nimmt `runHierarchy` entgegen und zeigt einen Hierarchie-Counter. | `RunHierarchyView.tsx` auf den neuen `runHierarchy`-Vertrag umstellen. Die Komponente erwartet aktuell weiterhin `runStates` und kann zur Laufzeit bei `runStates.forEach` fehlschlagen. Stabile IDs, Statusdarstellung, State-Links und Expand-Defaults umsetzen. Vollstaendigen Typecheck und UI-Test hinzufuegen. |
| 1C | `[OFFEN]` | Das Dashboard kann eine unvollstaendige Router-Sicht aus vorhandenen Main-State-Ergebnissen ableiten. | `Vorce-Orchestrator.ps1` muss `MainState.metadata.router_decision` wirklich persistieren. Configured/active/inactive Eintraege, Reasons, Evidence, Router-Key und Timestamp fehlen. Rueckwaertskompatibilitaet und State-Test fehlen. |
| 1D | `[TEILWEISE]` | `Test-Boot.ps1` prueft die 5 benannten MAIN-RUNs und mindestens einen gefundenen PART-RUN je gefundenem SUB-RUN. Dashboard-Build wurde ausgefuehrt. | Tests fuer exakt 5 MAIN, 17 SUB und 18 PART, 5 Root-Knoten, Config-Verknuepfungen, Routerdateien, Scriptregistrierung und Legacy-Orphans fehlen. Ein Fehlerfall-/Negativtest fehlt. |
| 2A-2D | `[TEILWEISE, NICHT ABGENOMMEN]` | Vier Auditdateien existieren unter `Vorce-Factory/audit-reports/`. | Reports gegen den aktuellen Code neu verifizieren. Widerspruechliche Aussagen zu State-Schema, Provider-Unterstuetzung und Dashboard-Hierarchie korrigieren. Offene Findings mit reproduzierbaren Tests belegen. |
| 3A-3C | `[TEILWEISE]` | Neue Einstiegspunkte `Vorce-Factory.ps1` und `Start-Vorce-Factory.ps1` existieren. Mehrere sichtbare UI-/Prompt-Namen wurden auf `Vorce-Factory` geaendert. | Verbleibende sichtbare Altbezeichnungen in aktiver Dokumentation bereinigen. Technische Altpfade, Kompatibilitaets-Aliase und Startskripte abschliessend testen und dokumentieren. |
| 4A | `[TEILWEISE]` | `Test-Boot.ps1` besteht mit 61/61 Checks. Die 5 erwarteten MAIN-RUN-Verzeichnisse werden gefunden. Alle aktuell gefundenen SUB-RUN-Skripte besitzen mindestens einen PART-RUN. | Dedizierten `Test-RunTopology.ps1` erstellen. Exakte Soll-Matrix 5/17/18 pruefen. Genau einen Router pro MAIN pruefen. Config-ID/Name/Script mit Ordnern kreuzvalidieren. Gleichnamige SUB-Skripte, exakte PART-Namen und interne PART-Registrierung pruefen. Dashboard-Hierarchie und Legacy-Orphans testen. Negativtests und ExitCode 1 bei Abweichung umsetzen. |

### Klare Abnahmeentscheidung fuer 4A

Bereits erledigt:

- [x] Die 5 erwarteten MAIN-RUN-Verzeichnisse existieren.
- [x] `Test-Boot.ps1` prueft diese 5 Namen.
- [x] Jeder aktuell gefundene SUB-RUN besitzt mindestens eine PART-RUN-Datei.
- [x] Der bestehende Boot-Test laeuft aktuell mit 61/61 Checks durch.

Noch offen:

- [ ] `Vorce-Factory/test/Test-RunTopology.ps1` erstellen.
- [ ] Exakt 5 MAIN-RUNs pruefen und zusaetzliche MAIN-RUNs erkennen.
- [ ] Exakt 17 SUB-RUNs pruefen und fehlende/zusaetzliche SUB-RUNs erkennen.
- [ ] Exakt 18 PART-RUNs pruefen und fehlende/zusaetzliche PART-RUNs erkennen.
- [ ] Pro MAIN-RUN genau einen korrekten Router pruefen.
- [ ] `router_rules` IDs, Namen und Scriptpfade gegen die Soll-Matrix pruefen.
- [ ] Gleichnamige SUB-RUN-Datei pro SUB-RUN-Ordner pruefen.
- [ ] Exakte PART-RUN-Namen und Parent-Zuordnung pruefen.
- [ ] Interne PART-RUN-Registrierung in jedem SUB-RUN-Skript pruefen.
- [ ] `/run-hierarchy.json` auf exakt 5/17/18 testen.
- [ ] Kanonische State-Dateien von echten Legacy-Orphans unterscheiden.
- [ ] Negativtests fuer fehlenden Router, falschen Config-Pfad und falschen PART-Parent implementieren.

**4A darf erst nach Erledigung aller offenen Checkboxen als `[ERLEDIGT]` markiert werden.**

Ausgefuehrte Verifikation:

- `npm run build` in `Vorce-Factory/web/Dashboard`: erfolgreich, aber ohne vollstaendigen Typecheck.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\Test-Boot.ps1`: 61/61 Checks bestanden.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\Test-OrchestratorDryRun.ps1`: 16/16 Checks bestanden.

Konsequenz fuer die weitere Umsetzung:

1. 1A, 1B, 1D, 2A-2D, 3A-3C und 4A bleiben `[TEILWEISE]`.
2. 1C bleibt `[OFFEN]`.
3. Kein Punkt darf auf `[ERLEDIGT]` gesetzt werden, bevor seine Spalte "Noch offen bis zur Abnahme" leer und durch Tests belegt ist.
4. Vor Punkt 4B muss der Datenvertrag zwischen `/run-hierarchy.json` und `RunHierarchyView.tsx` korrigiert und typgeprueft werden.
5. Auditberichte duerfen nur nach erneuter Codepruefung als Nachweis verwendet werden.

## Punkt 1: Dashboard-Run-Hierarchie korrekt bauen und Router-Aktivitaet visualisieren

### Prompt 1A - Backend/API: kanonische Run-Hierarchie statt flacher Run-State-Liste

```text
Du bist Agent fuer das Vorce-Factory Dashboard-Backend. Behebe die Run-Hierarchie-Datenquelle.

Ziel:
Das Dashboard darf die Run-Hierarchie nicht mehr aus flachen `var/run-states/*.json` Dateinamen erraten. Es muss eine kanonische Baumstruktur aus `Vorce-Factory/var/config/autopilot-config.json`, `Vorce-Factory/src/runs/**` und den neuesten Run-State-Dateien bauen.

Relevante Dateien:
- `Vorce-Factory/web/Dashboard/vite.config.ts`
- `Vorce-Factory/var/config/autopilot-config.json`
- `Vorce-Factory/src/runs/**`
- `Vorce-Factory/var/run-states/*.json`
- optional `Vorce-Factory/web/Dashboard/src/types.ts`

Bekannte Ist-Probleme:
- `/active-sessions.json` liefert `run_states` als flache Liste; dadurch zeigt die UI aktuell z.B. `43 Runs` mit MAIN- und PART-Knoten nebeneinander.
- Legacy-State-Dateien wie `PART_FetchIssues.json`, `PART_FetchPRs.json`, `PART_CreateProposal.json` tauchen als Root-Knoten auf.
- Sub-Run-State-Dateien haben teils kein `name`, sondern nur `sub_run`.
- Die Part-Run-Namen enthalten keinen `SUB-RUN-*` String, daher kann `RunHierarchyView.tsx` den Parent nicht korrekt extrahieren.

Aufgaben:
1. Implementiere in `vite.config.ts` eine robuste Funktion, z.B. `getRunHierarchy()`, die immer genau 5 MAIN-RUN Root-Knoten erzeugt.
2. Nutze `MAIN_RUNS` und `config.router_rules` als Source of Truth fuer alle konfigurierten Sub-Runs.
3. Ermittle fuer jeden Sub-Run den physischen Ordner und alle `PART-RUNS/PART-RUN-*.ps1`.
4. Mape Laufzeitdaten aus `var/run-states` nur als Status-/Timestamp-/Result-Anreicherung auf diese kanonischen Knoten.
5. Ignoriere State-Dateien, die nicht auf kanonische Runs matchen, oder markiere sie separat als `legacy_orphan_states`, aber nicht im eigentlichen Baum.
6. Liefere je Sub-Run mindestens diese Felder: `configured_enabled`, `router_active_last_run`, `runtime_status`, `activation_reason`, `inactive_reason`, `latest_state_path`, `part_runs`.
7. Aktive Sub-Runs sind aus dem letzten Main-Run-State ableitbar: `MAIN_*.json.results[].sub_run`. Falls ein Sub-Run dort nicht vorkommt, ist er im letzten Lauf inaktiv oder nicht ausgefuehrt.
8. Aktive Part-Runs sind die Part-Runs aus `results[].parts[]`; zusaetzlich muss der konfigurierte Part-Run aus der Ordnerstruktur sichtbar sein.
9. Stelle die Daten entweder ueber einen neuen Endpoint `/run-hierarchy.json` bereit oder erweitere `/active-sessions.json` um `run_hierarchy`. Bevorzuge einen neuen Endpoint, wenn das weniger Risiko fuer bestehende UI hat.

Akzeptanzkriterien:
- API liefert exakt 5 Main-Run-Knoten in der richtigen Reihenfolge.
- Unter jedem Main-Run stehen alle konfigurierten Sub-Runs aus der Soll-Struktur.
- Unter aktiven Sub-Runs stehen die verknuepften Part-Runs.
- Inaktive Sub-Runs werden sichtbar als inaktiv/ausgelassen markiert, nicht aus dem Baum geloescht.
- Keine Legacy-Part-States erscheinen als Root-Knoten.
- `npm run build` im Dashboard laeuft erfolgreich.
```

### Prompt 1B - Frontend: Tree-View exakt nach API-Baum rendern

```text
Du bist Frontend-Agent fuer `Vorce-Factory/web/Dashboard`. Ersetze die fehlerhafte Run-Hierarchie-Anzeige durch eine echte Baumansicht.

Ziel:
Die Dashboard-Karte "Run-Hierarchie" soll nicht mehr `43 Runs` als flache Liste zeigen, sondern exakt:
5 MAIN-RUNs -> deren SUB-RUNs -> deren PART-RUNs.
Router-Aktivitaet muss visuell klar sein: aktive Sub-Runs hervorgehoben, inaktive Sub-Runs gedimmt mit Grund, aktive Part-Runs unter aktiven Sub-Runs.

Relevante Dateien:
- `src/pages/DashboardPage.tsx`
- `src/components/RunHierarchyView.tsx`
- `src/App.tsx` falls globale Fetch-Logik genutzt wird
- `src/types.ts`
- Backend-Endpunkt aus Prompt 1A (`/run-hierarchy.json` oder `sessions.run_hierarchy`)

Bekannte Ist-Probleme:
- `DashboardPage.tsx` leitet `type` mit `state.name?.split('-')[0]` ab; das ergibt `main` nicht korrekt fuer `MAIN-RUN-...`.
- `RunHierarchyView.tsx` baut Parent-IDs mit Status im ID-String und sucht Parent-IDs mit anderem Muster. Dadurch brechen Parent-Child-Beziehungen.
- Part-Runs enthalten im Namen nur `MR-xx` und Sub-Run-Label, aber kein `SUB-RUN-xx`; Parent-Erkennung per Regex ist falsch.

Aufgaben:
1. Passe `RunHierarchyView` so an, dass sie eine bereits strukturierte Tree-API konsumiert. Keine Hierarchie mehr aus Dateinamen erraten.
2. Verwende stabile Node-IDs aus `mainRun.name`, `subRun.name`, `partRun.name`; Status darf nicht Teil der ID sein.
3. Anzeigeanforderung:
   - Main-Run: Name, Runtime-Status, letzter Start/Abschluss, Anzahl aktive/konfigurierte Sub-Runs.
   - Sub-Run: Name, Status-Badge `aktiv`, `inaktiv`, `config-disabled`, `not-run`, plus Grund.
   - Part-Run: Name, Status, Timestamp, JSON-State-Link falls vorhanden.
4. Der Counter oben soll nicht mehr alle Run-State-Dateien zaehlen, sondern z.B. `5 Main-Runs / 17 Sub-Runs / 18 Part-Runs` oder `5 MAIN-RUNs`.
5. JSON-Button darf nicht blind `/var/run-states/${name}.json` bauen. Nutze `latest_state_path` vom Backend.
6. Default: Alle Main-Runs expanded, aktive Sub-Runs expanded, inaktive Sub-Runs collapsed oder sichtbar gedimmt.
7. Halte Design konsistent mit existierendem Dashboard. Keine grosse Layout-Umgestaltung.

Akzeptanzkriterien:
- Visuell gibt es nur 5 Root-Knoten.
- Keine `unknown`, `PART_FetchIssues`, `PART_FilterIssues` oder andere alte Einzeldateien als Root-Knoten.
- Aktive vs. inaktive Sub-Runs sind ohne Klick erkennbar.
- `npm run build` laeuft erfolgreich.
```

### Prompt 1C - Router/State: Router-Entscheidungen explizit persistieren

```text
Du bist PowerShell-Agent fuer die Vorce-Factory Run-Orchestrierung. Ergaenze die Runtime-State-Informationen so, dass das Dashboard Router-Entscheidungen verlaesslich visualisieren kann.

Ziel:
Jeder MAIN-RUN-State soll nach dem Router-Aufruf dokumentieren, welche Sub-Runs konfiguriert waren, welche aktiv ausgefuehrt wurden und welche durch Router-Logik oder Config inaktiv waren.

Relevante Dateien:
- `Vorce-Factory/src/orchestrator/Vorce-Orchestrator.ps1`
- Router:
  - `src/runs/MAIN-RUN-01_Planning/Planning-Router.ps1`
  - `src/runs/MAIN-RUN-02_CheckAndDoing/CheckAndDoing-Router.ps1`
  - `src/runs/MAIN-RUN-03_Audit/Audit-Router.ps1`
  - `src/runs/MAIN-RUN-04_Optimizer/Optimizer-Router.ps1`
  - `src/runs/MAIN-RUN-05_MemoryOptimization/MemoryOptimization-Router.ps1`
- `src/lib/state/StateManager.ps1`
- `src/lib/engines/RunEngine.ps1`

Aufgaben:
1. Fuege nach dem Router-Aufruf in `Vorce-Orchestrator.ps1` `MainState.metadata.router_decision` hinzu.
2. Strukturvorschlag:
   `configured_sub_runs`, `active_sub_runs`, `inactive_sub_runs`, `router_key`, `decision_timestamp`.
3. Jeder Eintrag soll `id`, `name`, `script`, `configured_enabled`, `active`, `reason` enthalten.
4. Gruende:
   - `active_by_router`
   - `disabled_in_config`
   - `skipped_by_router_condition`
   - `script_missing`
   - `not_applicable`
5. Fuehre keine riskante Aenderung am Router-Vertrag ein, wenn es nicht noetig ist. Der Orchestrator kann aus Config + Router-Return bereits viel ableiten.
6. Falls Router selbst Gruende liefern sollen, erweitere rueckwaertskompatibel: bestehende `{id; name; script}` muessen weiterhin funktionieren.
7. Stelle sicher, dass MainState nach Abschluss mit Metadata gespeichert wird.

Akzeptanzkriterien:
- Neue `MAIN_MAIN-RUN-*.json` enthalten `metadata.router_decision`.
- Dashboard kann ohne erneutes Ausfuehren der Routerbedingungen sehen, was im letzten Lauf aktiv/inaktiv war.
- Bestehende Router- und Sub-Run-Aufrufe bleiben kompatibel.
- PowerShell-Syntax ist Windows PowerShell 5.1-kompatibel.
```

### Prompt 1D - Tests fuer die Dashboard-Hierarchie

```text
Du bist Test-Agent fuer Vorce-Factory. Erstelle fokussierte Tests fuer die Run-Hierarchie.

Ziel:
Absichern, dass die Dashboard-Hierarchie nie wieder zu einer flachen Liste aus Run-State-Dateien degradiert.

Relevante Dateien:
- `Vorce-Factory/test/Test-Boot.ps1`
- optional neuer Test `Vorce-Factory/test/Test-RunHierarchy.ps1`
- `Vorce-Factory/web/Dashboard/package.json`
- `Vorce-Factory/web/Dashboard/vite.config.ts`

Aufgaben:
1. Erstelle oder erweitere einen PowerShell-Test, der die Ordnerstruktur prueft:
   - exakt 5 MAIN-RUN-Verzeichnisse
   - alle 17 erwarteten SUB-RUN-Verzeichnisse
   - jeder SUB-RUN hat mindestens einen `PART-RUNS/PART-RUN-*.ps1`
2. Falls ein `/run-hierarchy.json` Endpoint existiert, dokumentiere einen manuellen oder automatisierten Check, der die 5 Root-Knoten validiert.
3. Ergaenze einen Test auf Legacy-Orphans: Dateien wie `PART_FetchIssues.json` duerfen nicht als Root-Run im Dashboard-Datensatz auftauchen.
4. Fuehre `npm run build` in `Vorce-Factory/web/Dashboard` aus.
5. Fuehre mindestens `.\test\Test-Boot.ps1` aus. Wenn DryRun sicher moeglich ist, auch `.\test\Test-OrchestratorDryRun.ps1`.

Akzeptanzkriterien:
- Tests schlagen fehl, wenn mehr oder weniger als 5 Main-Root-Knoten im Dashboard-Hierarchie-Datensatz sind.
- Tests schlagen fehl, wenn ein Sub-Run keinen Part-Run hat.
- Build- und Testresultate werden im Abschlussbericht genannt.
```

## Punkt 2: Alle Workflows, Codedateien und Verknuepfungen analysieren; Fehler finden und beheben

### Prompt 2A - Full-System-Audit fuer PowerShell Backend und Runtime-Pfade

```text
Du bist Senior-Audit-Agent fuer `Vorce-Factory`. Analysiere alle PowerShell-Codepfade, Module, Router, Sub-Runs, Part-Runs und Runtime-Verknuepfungen. Finde echte Fehler, nicht nur Stilfragen, und behebe eng begrenzte Defekte.

Scope:
- `Vorce-Factory/autopilot.ps1`
- `Vorce-Factory/Start-Autopilot.ps1`
- `Vorce-Factory/src/orchestrator/**`
- `Vorce-Factory/src/lib/**`
- `Vorce-Factory/src/runs/**`
- `Vorce-Factory/src/tools/services/**`
- `Vorce-Factory/test/**`

Pruefschwerpunkte:
1. Pfadauflösung: alle Module sollen `$global:VorceRoot`, `$global:VarDir`, `$global:LibDir`/ConfigBag nutzen; keine bruechigen relativen Pfade.
2. PowerShell 5.1-Kompatibilitaet: kein `??`, `?.`, `ForEach-Object -Parallel`, nicht-portable Syntax.
3. Dot-Sourcing und Funktionsverfuegbarkeit: Router nutzen z.B. `Test-VorceQuota`; pruefe, ob noetige Module geladen sind.
4. State-Schema-Konsistenz: MAIN/SUB/PART States muessen `name`, `type`, `status`, `started_at`, `completed_at`, `metadata`, `results` konsistent haben oder bewusst normalisiert werden.
5. Fehlerbehandlung: Part-Run Fehler duerfen Orchestrator nicht unkontrolliert crashen; Status muss persistiert werden.
6. JSON-I/O: leere/null Dateien, kaputte ConvertFrom-Json-Aufrufe, fehlende `-Depth`, Encoding.
7. Prozesssteuerung: keine fremden Prozesse anhand zu breiter CommandLine-Pattern beenden.

Vorgehen:
- Nutze `rg` und gezielte Dateireads, nicht blind alle Runtime-JSONs editieren.
- Fuehre relevante Tests aus: `.\test\Test-Boot.ps1`, `.\test\Test-OrchestratorDryRun.ps1`, optional `.\test\Test-PlanningRun.ps1`.
- Behebe nur klare Defekte. Dokumentiere Rest-Risiken separat.

Deliverable:
- Kurzer Auditbericht mit Findings nach Severity, Datei/Zeile, Fix oder Empfehlung.
- Liste der geaenderten Dateien.
- Testausgaben zusammengefasst.
```

### Prompt 2B - Dashboard/API-Audit fuer React/Vite und Datenvertraege

```text
Du bist Frontend/API-Audit-Agent fuer `Vorce-Factory/web/Dashboard`. Finde Fehler in React-Komponenten, Vite-Middleware, TypeScript-Typen, API-Endpunkten und Datenvertraegen.

Scope:
- `web/Dashboard/src/**`
- `web/Dashboard/vite.config.ts`
- `web/Dashboard/server/**`
- `web/Dashboard/package.json`
- keine `node_modules/`, `dist/` nur bei bewusstem Build.

Pruefschwerpunkte:
1. API-Datenvertrag: `/active-sessions.json`, `/run-catalog.json`, `/autopilot-config.json`, `/registry.json`, `/live-log.json`.
2. Run-Hierarchie: keine Typableitung per `split('-')`, keine Parent-Erkennung aus unvollstaendigen Namen.
3. UI-Robustheit: Null/Array-Faelle, leere Runtime-Dateien, kaputte Timestamps.
4. File-Links: JSON-Buttons sollen echte bekannte State-Pfade nutzen.
5. Doppelte/ungeutzte Imports und tote Komponenten, die Build/Lint brechen koennen.
6. Schreibende Endpoints: JSON speichern, Parent-Verzeichnisse, Fehlerantworten, keine Shell-Injection bei `gh`-Commands.
7. WebSocket/Sync: onFileUpdate muss die richtigen Daten refreshen.

Vorgehen:
- `npm run build` ausfuehren.
- Falls `npm run lint` existiert, ausfuehren und echte Fehler beheben.
- Keine UI-Neugestaltung, nur Fehler und Datenvertrag stabilisieren.

Deliverable:
- Findings mit Severity und Datei/Zeile.
- Fixes fuer klare Bugs.
- Build-/Lint-Ergebnis.
```

### Prompt 2C - GitHub-Workflows und Repo-Verknuepfungen auditieren

```text
Du bist CI/Workflow-Audit-Agent. Analysiere `.github/workflows`, `.github/commands`, Issue-Templates, Labels und die Vorce-Factory-Skripte, die GitHub/Jules/PRs beruehren.

Scope:
- `.github/workflows/*.yml`
- `.github/commands/*.toml`
- `.github/ISSUE_TEMPLATE/*`
- `.github/labels.yml`, `.github/dependabot.yml`, `.github/codeql-config.yml`
- `scripts/jules/**`
- `Vorce-Factory/src/lib/integrations/GitHubClient.ps1`
- `Vorce-Factory/src/lib/utils/ProjectManager.ps1`
- Part-Runs, die `gh` aufrufen.

Pruefschwerpunkte:
1. Workflow-Trigger, Permissions, Secrets, Checkout, Cache, Artifacts.
2. Namens- und Label-Konventionen: `autopilot-created`, `jules-task`, `status:*`, `agent:*`.
3. PR-/Issue-Flow: keine widerspruechlichen Jobnamen, keine doppelten Monitor-Jobs mit kollidierenden Outputs.
4. Shell-Kompatibilitaet auf Windows/self-hosted.
5. Robustheit gegen fehlendes `gh`, fehlende Auth, Rate Limits.
6. Sicherheitsrisiken: unsanitized Issue/PR-Titel in Shell-Kommandos.

Vorgehen:
- Keine Workflow-Neuarchitektur. Fixe konkrete Defekte.
- Wenn ein externer Provider/Runner nicht pruefbar ist, dokumentiere Annahmen.

Deliverable:
- Auditbericht mit Datei/Zeile und konkreter Empfehlung/Fix.
- Liste aller geaenderten Workflow-/Script-Dateien.
```

### Prompt 2D - Runtime-State, Prompt-Registry und Datenhygiene auditieren

```text
Du bist Daten-/Prompt-Audit-Agent fuer Vorce-Factory. Pruefe Runtime-State-Dateien, Prompt-Registry, Prompt-Dateien und Datenbank-JSONs auf Inkonsistenzen, die Dashboard oder Orchestrator brechen.

Scope:
- `Vorce-Factory/var/config/*.json`
- `Vorce-Factory/var/prompts/**`
- `Vorce-Factory/var/db/*.json`
- `Vorce-Factory/var/run-states/*.json`
- `Vorce-Factory/src/lib/utils/PromptManager.ps1`

Regeln:
- Runtime-Dateien duerfen nicht blind geloescht werden.
- Wenn Cleanup noetig ist, erst Sicherungs-/Migrationsstrategie vorschlagen oder Legacy-Dateien im Code ignorieren.
- Prompt-Inhalt nur minimal aendern, wenn er technisch falsch ist.

Pruefschwerpunkte:
1. `prompt-registry.json`: jeder Pfad existiert, keine toten Registry-IDs.
2. Run-State Schema: MAIN/SUB/PART-Namen konsistent; Legacy-States identifizieren.
3. Config: `router_rules` decken alle realen Sub-Runs ab; `wake_intervals` decken alle Main-Runs ab.
4. Dashboard-State und Global-State: keine `null`, keine leeren Dateien, keine bruechigen Felder.
5. Naming: alte `Vorce-Autopilot_2.0`/`Vorce-Autopilot_NEW` Referenzen in aktiver Doku markieren.

Deliverable:
- Tabelle: Datei, Problem, Risiko, empfohlene Aktion.
- Fixes nur fuer risikoarme, eindeutige Inkonsistenzen.
```

## Punkt 3: Vorce-Autopilot_3.0 / Autopilot gegen Vorce-Factory tauschen

### Prompt 3A - Produktname im aktiven Vorce-Factory-System ersetzen

```text
Du bist Rename-Agent. Ersetze sichtbare Produkt-/Systembezeichnungen `Vorce-Autopilot_3.0`, `Vorce-Autopilot NEW`, `Vorce Autopilot`, `Vorce-Autopilot`, `Autopilot` dort, wo sie als Produktname gemeint sind, durch `Vorce-Factory`.

Scope:
- `Vorce-Factory/*.md`
- `Vorce-Factory/web/Dashboard/src/**`
- `Vorce-Factory/web/Dashboard/index.html`
- `Vorce-Factory/web/Dashboard/*.md`
- `Vorce-Factory/var/prompts/**`
- Kommentare und sichtbare UI-Texte in `Vorce-Factory/src/**`

Wichtige Ausnahmen:
- Technische Dateinamen, Scriptnamen und API-Pfade nicht blind umbenennen: `autopilot.ps1`, `Start-Autopilot.ps1`, `autopilot-config.json`, `autopilot-service.log`, `autopilot.wakeup`, `autopilot-created`.
- Diese technischen Namen duerfen nur geaendert werden, wenn du eine Kompatibilitaetsstrategie mit Aliases/Migration implementierst. Fuer diesen Auftrag reicht sichtbares Branding.

Aufgaben:
1. Nutze `rg -n "Vorce-Autopilot_3\\.0|Vorce-Autopilot|Vorce Autopilot|Autopilot|autopilot"`.
2. Klassifiziere jeden Treffer: `visible_branding`, `technical_identifier`, `label/api/path`, `historical_doc`.
3. Ersetze nur `visible_branding` durch `Vorce-Factory`.
4. In UI: Header, Footer, Titel, H2, Dokumentationstitel ersetzen.
5. In Prompts: Rollenformulierungen wie "Du bist der ... des Vorce-Autopiloten" zu "Du bist ... der Vorce-Factory".
6. Lasse Label `autopilot-created` unveraendert, wenn es GitHub-Kompatibilitaet sichert.

Akzeptanzkriterien:
- Dashboard zeigt `Vorce-Factory`, nicht `Vorce Autopilot`.
- Aktive Doku spricht von `Vorce-Factory`.
- Kein technischer Startpfad ist gebrochen.
- `npm run build` im Dashboard erfolgreich.
```

### Prompt 3B - Repo-weite Altbezeichnungen bereinigen und Resttreffer dokumentieren

```text
Du bist Repo-Rename-Audit-Agent. Suche repo-weit nach alten Autopilot-Bezeichnungen und bereinige sie, soweit sie nicht technische Kompatibilitaet betreffen.

Scope:
- gesamtes Repo, aber ausschliessen: `**/node_modules/**`, `target/**`, generierte `dist/**` wenn nicht bewusst neu gebaut.
- Besonders: `docs/**`, `scripts/**`, `Vorce-Factory/**`, `.github/**`.

Regeln:
1. Neue Bezeichnung ist exakt `Vorce-Factory`.
2. Historische Dokumente duerfen alte Namen behalten, wenn sie alte Versionen beschreiben; fuege dann optional einen Hinweis hinzu: "Historische Referenz, aktueller Name: Vorce-Factory".
3. Technische Dateinamen und IDs nur mit Migrationsplan aendern.
4. Keine grossflaechige Formatierung.

Deliverable:
- Liste geaenderter Dateien.
- Liste verbleibender Altbezeichnungs-Treffer mit Grund, warum sie bleiben.
- Build/Test, soweit betroffen.
```

### Prompt 3C - Rename-Kompatibilitaet pruefen

```text
Du bist Validierungs-Agent fuer das Rename von `Autopilot` zu `Vorce-Factory`.

Ziel:
Nach Rename duerfen Startskripte, Dashboard-Endpunkte, Config-Dateien, GitHub Labels und Tests nicht brechen.

Pruefe:
- `.\Vorce-Factory\test\Test-Boot.ps1`
- `.\Vorce-Factory\test\Test-OrchestratorDryRun.ps1`
- `npm run build` in `Vorce-Factory/web/Dashboard`
- `rg -n "Vorce Autopilot|Vorce-Autopilot|Vorce-Autopilot_3\\.0|Vorce-Autopilot_NEW" -g '!**/node_modules/**' -g '!target/**'`

Akzeptanzkriterien:
- Keine alten sichtbaren Produktnamen in aktiver UI/Doku.
- Verbleibende Treffer sind technische oder historische Ausnahmen und dokumentiert.
- Keine Start-/Build-Regression.
```

## Punkt 4: Run-Topologie, Router und State-Vertraege eindeutig absichern

Arbeitsregel fuer Punkt 4:

- Keine Run-Datei nur wegen ihres Namens automatisch als korrekt betrachten.
- Config, Ordnerstruktur, Router-Rueckgabe und State-Dateien muessen dieselbe kanonische Identitaet verwenden.
- Tests muessen bei Abweichungen mit ExitCode ungleich 0 enden und den exakten Run nennen.
- Bestehende Runtime-Dateien nicht loeschen. Legacy-Dateien nur erkennen, ignorieren oder separat ausweisen.

Status: [TEILWEISE] Die Topologie ist dokumentiert, aber Validator, Router-Abnahme und Negativtests sind noch offen.

### Prompt 4A - Vollstaendigen Topologie-Validator mit exakter Soll-Matrix bauen

```text
Du bist Struktur-Validierungs-Agent. Implementiere einen dedizierten, deterministischen Topologie-Test. Ersetze nicht nur einzelne Checks in `Test-Boot.ps1`, sondern erstelle die fachliche Hauptpruefung in:

- neu: `Vorce-Factory/test/Test-RunTopology.ps1`
- Anpassung: `Vorce-Factory/test/Test-Boot.ps1`
- Eingaben:
  - `Vorce-Factory/var/config/autopilot-config.json`
  - `Vorce-Factory/src/runs/**`

Ziel:
Der Test muss exakt pruefen, dass die aktuelle Soll-Topologie aus 5 MAIN-RUNs, 17 SUB-RUNs und 18 PART-RUNs besteht. Spaetere, bewusst in Punkt 9 eingefuehrte Runs duerfen erst zusammen mit einer Aktualisierung dieser Soll-Matrix hinzukommen.

Kanonische Soll-Matrix fuer den aktuellen Stand:

1. `MAIN-RUN-01_Planning`
   - Router: `Planning-Router.ps1`
   - `SUB-RUN-01_MR-01_Planning__DataSync`
     - `PART-RUN-01_MR-01_Planning__DataSync__FetchIssues`
     - `PART-RUN-02_MR-01_Planning__DataSync__FetchPRs`
   - `SUB-RUN-02_MR-01_Planning__Triage`
     - `PART-RUN-01_MR-01_Planning__Triage__FilterIssues`
   - `SUB-RUN-03_MR-01_Planning__Strategy`
     - `PART-RUN-01_MR-01_Planning__Strategy__CreateProposal`
   - `SUB-RUN-04_MR-01_Planning__Delegation`
     - `PART-RUN-01_MR-01_Planning__Delegation__CreateDelegations`
2. `MAIN-RUN-02_CheckAndDoing`
   - Router: `CheckAndDoing-Router.ps1`
   - `SessionSync` -> `SyncActiveSessions`
   - `JulesCheck` -> `InspectJulesSessions`
   - `LocalAgentCheck` -> `InspectLocalAgents`
   - `ReviewDispatch` -> `DispatchReviews`
   - `JulesRefill` -> `RefillJulesQueue`
   - `Housekeeping` -> `CleanupRuntimeState`
   - Alle Namen muessen den vollstaendigen `SUB-RUN-xx_MR-02_...` bzw. `PART-RUN-xx_MR-02_...` Praefix besitzen.
3. `MAIN-RUN-03_Audit`
   - Router: `Audit-Router.ps1`
   - `DataSync` -> `ValidateDataSources`
   - `ComplianceCheck` -> `EvaluateCompliance`
   - `JulesSupervision` -> `SuperviseJulesSessions`
   - `AlertDisposition` -> `DispositionAlerts`
4. `MAIN-RUN-04_Optimizer`
   - Router: `Optimizer-Router.ps1`
   - `PerformanceDataCollection` -> `CollectPerformanceMetrics`
   - `SystemAnalysis` -> `AnalyzeSystemPerformance`
5. `MAIN-RUN-05_MemoryOptimization`
   - Router: `MemoryOptimization-Router.ps1`
   - `MemoryMaintenance` -> `OptimizeMemoryStore`

Teilaufgaben:

4A.1 - Soll-Manifest definieren
- Definiere am Anfang von `Test-RunTopology.ps1` eine lesbare Hashtable mit Main-Name, Router-Datei, Router-Key, Sub-Name, Config-Name, Sub-ID und erwarteten Part-Namen.
- Keine Soll-Werte aus der zu pruefenden Ordnerstruktur generieren. Sonst bestaetigt der Test nur den Ist-Zustand.

4A.2 - MAIN-RUNs pruefen
- Unter `src/runs` muessen exakt die 5 erwarteten `MAIN-RUN-*` Verzeichnisse existieren.
- Pro MAIN-RUN muss genau eine `*-Router.ps1` Datei existieren.
- Der Router-Dateiname muss dem Soll-Manifest entsprechen.
- Zusaetzliche MAIN-RUN-Verzeichnisse sind ein Fehler, bis das Manifest bewusst aktualisiert wurde.

4A.3 - SUB-RUNs pruefen
- Pro MAIN-RUN muessen exakt die erwarteten SUB-RUN-Verzeichnisse existieren.
- Jeder SUB-RUN-Ordner muss eine gleichnamige `.ps1` Datei enthalten.
- Die Nummer im Ordnernamen, Dateinamen und Config-Feld `id` muss identisch sein.
- Die Kombination aus Main-Run, Sub-ID und fachlichem Namen muss eindeutig sein.

4A.4 - PART-RUNs pruefen
- Jeder SUB-RUN muss genau einen Ordner `PART-RUNS` besitzen.
- Darin muessen exakt die im Manifest erwarteten PART-RUN-Dateien existieren.
- Der PART-RUN-Name muss die richtige `MR-xx` Nummer, den Main-Namen und den Parent-Sub-Namen enthalten.
- Doppelte PART-IDs innerhalb eines SUB-RUNs sind ein Fehler.
- Leere `PART-RUNS` Ordner sind ein Fehler.

4A.5 - Config-Verknuepfung pruefen
- `router_rules` muss exakt die Keys `Planning`, `CheckAndDoing`, `Audit`, `Optimizer`, `MemoryOptimization` enthalten.
- Jeder erwartete SUB-RUN muss genau einmal im richtigen Router-Key stehen.
- `rule.id`, `rule.name` und `rule.script` muessen dem Manifest entsprechen.
- `rule.script` muss relativ zum Repo-Root auf die gleichnamige SUB-RUN-Datei zeigen.
- Ein Config-Eintrag ohne realen Ordner oder ein realer SUB-RUN ohne Config-Eintrag ist ein Fehler.
- `enabled=false` ist erlaubt und kein Topologiefehler.

4A.6 - Skriptinterne PART-Registrierung pruefen
- Lies die SUB-RUN-Datei als Text und pruefe fuer jeden erwarteten PART-RUN, dass dessen voller Name und dessen `.ps1` Pfad registriert werden.
- Pruefe, dass die SUB-RUN-Datei `Invoke-VorceSubRunSequential` oder `Invoke-VorceSubRunParallel` aufruft.
- Dieser Textcheck ist zusaetzlich zur Dateipruefung erforderlich, weil vorhandene PART-Dateien sonst ungenutzt bleiben koennen.

4A.7 - Dashboard-Hierarchie pruefen
- Fuege einen testbaren Export oder ein kleines Node-Testskript fuer `getRunHierarchy()` hinzu.
- Ergebnis muss exakt 5 Root-Knoten enthalten.
- Aktuelle Soll-Zahlen: 17 SUB-RUNs und 18 PART-RUNs.
- `legacy_orphan_states` darf kanonische Dateien wie `PART_PART-RUN-01_...json` nicht als Legacy klassifizieren.
- Kein Legacy-State darf in `main_runs` als Root auftauchen.

4A.8 - Testintegration
- `Test-Boot.ps1` soll `Test-RunTopology.ps1` aufrufen oder mindestens auf dessen Existenz verweisen. Keine doppelte, abweichende Soll-Matrix pflegen.
- Fuehre aus:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\Test-RunTopology.ps1`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\Test-Boot.ps1`
  - den Node-/API-Hierarchietest
- Fuehre zusaetzlich einen Negativtest mit temporaerem Fixture aus: fehlender Router, falscher Config-Pfad und PART-RUN ohne Parent muessen erkannt werden.

Ausgabeformat:
- Pro Check `[PASS]` oder `[FAIL]`.
- Bei Fehlern immer Sollwert, Istwert und konkreter Pfad.
- Am Ende Gesamtzahlen fuer MAIN/SUB/PART und ExitCode 1 bei mindestens einem Fehler.

Akzeptanzkriterien:
- Exakt 5/17/18 werden validiert.
- Router, Config, Ordner, Sub-Skripte und registrierte Part-Skripte werden kreuzvalidiert.
- Der aktuelle Test kann nicht mehr gruen sein, wenn nur "irgendein" PART-RUN pro SUB-RUN existiert.
- Windows PowerShell 5.1-kompatibel.
- Punkt 4A gilt erst als abgeschlossen, wenn der neue dedizierte Test und die Negativtests vorhanden sind.
```

### Prompt 4B - Router-Regeln exakt definieren und im Dashboard einfach editierbar machen

```text
Du bist Router- und Dashboard-Konfigurations-Agent. Vereinheitliche die Router aller 5 MAIN-RUNs. Implementiere keine frei editierbaren PowerShell-Ausdruecke im Dashboard. Nutze eine kleine Whitelist sicherer Bedingungstypen.

Zu aendernde Dateien:

- `Vorce-Factory/var/config/autopilot-config.json`
- `Vorce-Factory/src/orchestrator/Vorce-Orchestrator.ps1`
- `Vorce-Factory/src/runs/MAIN-RUN-01_Planning/Planning-Router.ps1`
- `Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/CheckAndDoing-Router.ps1`
- `Vorce-Factory/src/runs/MAIN-RUN-03_Audit/Audit-Router.ps1`
- `Vorce-Factory/src/runs/MAIN-RUN-04_Optimizer/Optimizer-Router.ps1`
- `Vorce-Factory/src/runs/MAIN-RUN-05_MemoryOptimization/MemoryOptimization-Router.ps1`
- neu oder bestehend: zentraler Helper unter `Vorce-Factory/src/lib/engines/RouterEngine.ps1`
- `Vorce-Factory/web/Dashboard/src/types.ts`
- `Vorce-Factory/web/Dashboard/src/pages/SettingsPage.tsx`
- `Vorce-Factory/web/Dashboard/vite.config.ts`
- neu: `Vorce-Factory/test/Test-Routers.ps1`

Ziel-Datenvertrag pro `router_rules` Eintrag:

{
  "id": "01",
  "name": "DataSync",
  "script": "src/runs/...",
  "enabled": true,
  "mode": "always|automatic|manual_only",
  "condition": "always",
  "condition_settings": {},
  "dashboard_editable": true
}

Zulaessige Condition-Keys:

- `always`
- `pipeline_below_limit`
- `has_untriaged_issues`
- `has_approved_proposals`
- `has_active_jules_delegations`
- `has_active_local_agent_sessions`
- `has_open_prs_requiring_review`
- `jules_capacity_available`
- `housekeeping_due`
- `has_new_audit_inputs`
- `has_open_alerts`
- `optimizer_has_sufficient_samples`
- `optimizer_has_findings`
- `optimizer_has_approved_changes`
- `optimizer_has_changes_to_evaluate`
- `memory_maintenance_due`
- `memory_has_candidates`
- `master_issue_context_changed`

Keine `Invoke-Expression`, keine ScriptBlocks aus JSON und keine frei eingebbaren Shell-Kommandos.

Verbindliche Router-Matrix:

1. Planning
- `DataSync`: `mode=always`, `condition=always`. Darf innerhalb eines fortgesetzten Main-Runs durch einen gueltigen Checkpoint wiederverwendet werden.
- `Triage`: `mode=automatic`, `condition=has_untriaged_issues`. Aktiv, wenn der aktuelle DataSync-Snapshot neue oder geaenderte Issues enthaelt oder kein gueltiges Triage-Ergebnis fuer den Snapshot existiert.
- `Strategy`: `mode=automatic`, `condition=pipeline_below_limit`. Aktiv, wenn `eligible_triaged_count + pending_proposals < max_issues_per_planning_cycle`. Nicht allein anhand der Gesamtzahl aller GitHub-Issues entscheiden.
- `Delegation`: `mode=automatic`, `condition=has_approved_proposals`. Aktiv, wenn mindestens ein noch nicht delegierter, freigegebener Vorschlag existiert und Zielprovider/Jules Kapazitaet besitzt.

2. CheckAndDoing
- `SessionSync`: `mode=always`, `condition=always`.
- `JulesCheck`: `condition=has_active_jules_delegations`.
- `LocalAgentCheck`: `condition=has_active_local_agent_sessions`. Nutze bevorzugt eine PID-/Session-Registry; kein breites `Get-Process` Regex als einzige Quelle.
- `ReviewDispatch`: `condition=has_open_prs_requiring_review`. Drafts und bereits erledigte Reviews ausschliessen.
- `JulesRefill`: `condition=jules_capacity_available`. Zusaetzlich muessen `monitoring_refill_enabled=true`, freie Slots, Quota und delegierbare Tasks vorhanden sein.
- `Housekeeping`: `condition=housekeeping_due`. Nur aktiv, wenn Cleanup-Intervall erreicht ist oder abgelaufene TMP-/Lock-Dateien existieren; nicht automatisch bei jedem 15-Minuten-Lauf.

3. Audit
- `DataSync`: `mode=always`, `condition=always`.
- `ComplianceCheck`: `condition=has_new_audit_inputs`. Aktiv bei neuen Merge-/Run-/Workflow-Daten oder wenn ein konfigurierbares Maximalintervall erreicht ist.
- `JulesSupervision`: `condition=has_active_jules_delegations`.
- `AlertDisposition`: `condition=has_open_alerts`.

4. Optimizer
- `PerformanceDataCollection`: `mode=always`, `condition=always`.
- `SystemAnalysis`: `condition=optimizer_has_sufficient_samples`; Default mindestens 3 abgeschlossene relevante Runs.
- Die in Punkt 9 neu eingefuehrten Sub-Runs erhalten die dort definierten Conditions.

5. MemoryOptimization
- Bestehendes `MemoryMaintenance`: bis Punkt 9 `condition=memory_maintenance_due`.
- Nach Punkt 9 werden die neuen Memory-Sub-Runs gemaess der dortigen Matrix eingetragen.

Teilaufgaben:

4B.1 - Zentralen Router-Helper implementieren
- `Resolve-VorceRouterDecision` bekommt Main-Name, ConfigBag, MainState und die kanonischen Regeln.
- Rueckgabe pro SUB-RUN:
  `{ id, name, script, configured_enabled, mode, condition, active, reason, evidence }`
- Fehlerhafte Datenquellen duerfen nicht crashen. Ergebnis ist in diesem Fall inaktiv mit `reason=data_source_unavailable`, ausser ein `always` Run ist betroffen.

4B.2 - Router kompatibel halten
- Die Router duerfen weiterhin ein Array aktiver Runs an den Orchestrator liefern.
- Zusaetzlich schreiben sie oder der Orchestrator die vollstaendige Decision-Liste in `MainState.metadata.router_decision`.
- Aktive Eintraege behalten mindestens `{id; name; script}`.

4B.3 - Exakte Reasons verwenden
- `active_always`
- `active_condition_met`
- `disabled_in_config`
- `manual_only`
- `condition_not_met`
- `dependency_not_ready`
- `data_source_unavailable`
- `script_missing`
- `reused_from_checkpoint`

4B.4 - Dashboard-Einstellungen vereinfachen
- In `SettingsPage.tsx` pro SUB-RUN nur diese Router-Kontrollen anzeigen:
  - Toggle `Aktiv`
  - Segmented control `Immer | Automatisch | Nur manuell`
  - Dropdown mit den fuer diesen SUB-RUN erlaubten Condition-Keys
  - kleine numerische Felder nur fuer whitelisted Settings, z.B. Mindest-Samples oder Intervall
- Scriptpfad und ID nur lesbar anzeigen, nicht frei editierbar.
- Vor dem Speichern eine kurze Zusammenfassung anzeigen: "Planning/Strategy: automatisch bei freier Pipeline".
- Keine komplexe Rule-Builder-UI.

4B.5 - API validieren
- `/api/config` darf nicht blind beliebiges JSON speichern.
- Vor dem Schreiben:
  - alle 5 Router-Keys vorhanden
  - IDs/Namen/Scripts gegen Run-Katalog pruefen
  - `mode` und `condition` gegen Whitelist pruefen
  - numerische Grenzwerte begrenzen
- Bei Fehler HTTP 400 mit Feldpfad und Meldung.
- Vor erfolgreichem Schreiben Backup nach `var/config/backups/autopilot-config-<timestamp>.json`.

4B.6 - Tests
- `Test-Routers.ps1` verwendet Fixtures/Mock-ConfigBag und prueft jede Condition mindestens einmal true und false.
- Fehlendes `gh`, leere JSON-Datei und fehlende optionale State-Felder duerfen keinen Router-Crash verursachen.
- Teste, dass `enabled=false` immer Vorrang hat.
- Teste, dass `manual_only` bei normalem Scheduler inaktiv und bei explizitem Force aktiv ist.
- Teste, dass alle aktiven Scripts existieren.

Akzeptanzkriterien:
- Alle Routerentscheidungen sind deterministisch, begruendet und im Main-State gespeichert.
- Dashboard kann einfache Anpassungen vornehmen, ohne Code oder PowerShell-Ausdruecke zu editieren.
- Router und Dashboard nutzen denselben Config-Vertrag.
- Keine Routerentscheidung basiert ausschliesslich auf unsicheren Prozessnamen oder einer unklaren Gesamtzahl.
- `Test-Routers.ps1`, `Test-RunTopology.ps1`, `Test-Boot.ps1` und Dashboard-Typecheck bestehen.
```

### Prompt 4C - RunEngine, Checkpoints und State-Schema konsolidieren

```text
Du bist RunEngine-/State-Agent. Vereinheitliche MAIN-, SUB- und PART-State-Dateien als Grundlage fuer Dashboard, Logging, Fallback-Resume und Statistiken.

Zu aendernde Dateien:
- `Vorce-Factory/src/lib/engines/RunEngine.ps1`
- `Vorce-Factory/src/lib/state/StateManager.ps1`
- `Vorce-Factory/src/orchestrator/Vorce-Orchestrator.ps1`
- alle `Vorce-Factory/src/runs/**/SUB-RUN-*.ps1`
- Tests: neu `Vorce-Factory/test/Test-RunStateSchema.ps1`

Verbindliche gemeinsame Felder:

{
  "schema_version": 2,
  "id": "run_<timestamp>_<random>",
  "main_run_id": "...",
  "parent_run_id": null,
  "name": "vollstaendiger kanonischer Name",
  "type": "MAIN|SUB|PART",
  "status": "initialized|running|waiting_provider|completed|failed|skipped|reused",
  "started_at": "...",
  "completed_at": null,
  "duration_ms": null,
  "input_fingerprint": "...",
  "metadata": {},
  "results": []
}

Teilaufgaben:
1. `Initialize-RunState` muss Parent-/Main-IDs und optionalen Input-Fingerprint annehmen.
2. `Save-VorceRunState` schreibt weiterhin eine Latest-Datei und zusaetzlich eine immutable History-Datei unter `var/run-history/<type>/<name>/<id>.json`.
3. SUB-Aggregate enthalten immer `name`, `type="SUB"`, `status`, `started_at`, `completed_at`, `duration_ms`, `parts`.
4. PART-States verwenden immer den vollstaendigen PART-RUN-Namen.
5. `run_settings` ist optional. Jeder Zugriff muss Null-sicher sein.
6. Parallel-Jobs muessen das finale State-Objekt verlaesslich genau einmal zurueckgeben. Streaming-Ausgabe darf das Objekt nicht verschlucken.
7. Legacy-State-Dateien werden nicht geloescht. Neue Logik liest bevorzugt Schema 2 und kennzeichnet Schema 1 als Legacy.
8. Fuege Helper fuer `completed`, `failed`, `skipped`, `waiting_provider` hinzu, damit Statuswechsel nicht an vielen Stellen manuell gebaut werden.

Akzeptanzkriterien:
- Neue MAIN/SUB/PART States sind schema-konsistent.
- Latest- und History-Datei enthalten denselben finalen Status.
- Fehlendes `run_settings` verursacht keinen Null-Property-Fehler.
- Punkt 6C kann auf Basis dieser States abgeschlossene Parts wiederverwenden.
```

## Punkt 5: Logging und Run-Statistiken belastbar machen

Status: [TEILWEISE] Logging- und Summary-Grundlage ist begonnen, aber der belastbare End-to-End-Nachweis fehlt noch.

### Prompt 5A - Zentrales strukturiertes Logging als Funktionsmodul implementieren

```text
Du bist Logging-Core-Agent. Logging ist ein Kernbestandteil und muss vor Dashboard-Statistiken, Provider-Fallback und Optimizer stabil sein.

Zu aendernde Dateien:
- `Vorce-Factory/src/lib/logging/Write-Log.ps1`
- `Vorce-Factory/src/lib/utils/StatusPrinter.ps1`
- `Vorce-Factory/Vorce-Factory.ps1`
- optionaler Kompatibilitaets-Alias `Vorce-Factory/autopilot.ps1`, falls dieser beibehalten wird
- `Vorce-Factory/src/orchestrator/Vorce-Orchestrator.ps1`
- `Vorce-Factory/src/lib/engines/RunEngine.ps1`
- `Vorce-Factory/src/lib/integrations/AgentRunner.ps1`
- `Vorce-Factory/src/tools/services/sync-service.ps1`
- neu: `Vorce-Factory/test/Test-Logging.ps1`

Ist-Defizite:
- `Write-Log.ps1` besitzt Mandatory-Parameter auf Skript-Top-Level und ist daher nicht sicher dot-sourcebar.
- `StatusPrinter.ps1` schreibt nur Terminaltext.
- `Vorce-Factory.ps1` besitzt eine zweite lokale Logfunktion.
- Background-Jobs, Router, Provider-Versuche und State-Wechsel haben keinen gemeinsamen Event-Vertrag.

Verbindliche Log-Sinks:
1. Terminal: kurze menschenlesbare Zeilen.
2. Session-Textlog: `var/log/sessions/<session_id>.log`.
3. Strukturiertes JSONL: `var/log/events/vorce-events-YYYYMMDD.jsonl`.
4. Fehlerlog: `var/log/vorce-errors.log`.
5. Keine Dashboard-Live-Log-Datei als Pflicht. Punkt 5C nutzt aggregierte Run-Daten.

Verbindliches Event-Schema:

{
  "timestamp": "ISO-8601",
  "level": "DEBUG|INFO|WARN|ERROR|FATAL",
  "event_type": "run_started|run_completed|run_failed|run_skipped|provider_attempt|provider_fallback|state_saved|process_started|process_stopped|cleanup|diagnostic",
  "component": "orchestrator|run-engine|router|agent-runner|sync-service|dashboard|bootstrap",
  "session_id": "...",
  "correlation_id": "...",
  "main_run_id": null,
  "sub_run_id": null,
  "part_run_id": null,
  "run_name": null,
  "provider": null,
  "attempt": null,
  "status": null,
  "duration_ms": null,
  "message": "kurz",
  "data": {},
  "pid": 0
}

Teilaufgaben:

5A.1 - Modulform korrigieren
- Entferne alle Top-Level-Mandatory-Parameter aus `Write-Log.ps1`.
- Implementiere `Write-VorceLogEntry`.
- Optionaler Wrapper `Write-Log` darf fuer alte Aufrufer bleiben.
- Dot-Sourcing darf keine Ausgabe, keinen Prompt und keinen Fehler erzeugen.

5A.2 - Kontext erzeugen und weiterreichen
- Beim Start genau eine `session_id` erzeugen.
- Pro MAIN-RUN eine `correlation_id` bzw. `main_run_id`.
- IDs ueber `ConfigBag` und Job-Argumente an Router, SUB-, PART- und Provider-Aufrufe weiterreichen.
- Keine neue Main-ID bei einem Resume aus Punkt 6C.

5A.3 - StatusPrinter anbinden
- `Write-VorceStep`, `Write-VorceRunStart`, `Write-VorceRunEnd`, `Write-VorceHeader`, `Write-VorceFooter` duerfen weiterhin Terminalfarben nutzen.
- RunStart/RunEnd muessen zusaetzlich strukturierte Events schreiben.
- Reine dekorative Header/Divider muessen nicht in JSONL geloggt werden.
- Verhindere Doppellogs, wenn ein Wrapper intern einen anderen Wrapper aufruft.

5A.4 - Pflicht-Events definieren
- MAIN/SUB/PART: initialized, started, completed, failed, skipped, reused.
- Router: Entscheidung mit Condition, Reason und kleiner Evidence.
- Provider: attempt_started, attempt_failed, fallback_selected, attempt_succeeded, chain_exhausted.
- State: save_failed immer ERROR; normale Saves nur DEBUG oder `state_saved`.
- Prozess: PID, Komponente, Port, WorkingDirectory, stdout/stderr.

5A.5 - Fehlerdetails
- ERROR/FATAL immer in JSONL, Session-Log und `vorce-errors.log`.
- Felder: `error_class`, Exception-Typ, kurze Meldung, betroffener Run, Provider, ExitCode, Artefaktpfad.
- Stacktrace nur bei Debug oder in separatem Artefakt, nicht als endlose Terminalzeile.

5A.6 - Redaction
- Vor jedem Sink typische Secrets maskieren:
  - `Authorization: Bearer ...`
  - GitHub Tokens `ghp_`, `github_pat_`
  - API-Key-Zuweisungen
  - bekannte Auth-Env-Variablen aus Provider-Registry
- Prompts und komplette LLM-Outputs nie in Standardlogs.
- Maximaler `message`-Text 500 Zeichen; groessere Inhalte als Artefakt.

5A.7 - Background-Jobs
- `Start-Job` bekommt Log-Kontext und Logpfade explizit.
- Parallele Jobs muessen atomar eine JSONL-Zeile schreiben koennen; verwende File-Lock/Mutex oder pro Job eine temporaere Eventdatei mit spaeterem Merge.
- Kein vermischtes, unparsebares JSONL.

5A.8 - Tests
- Dot-Source-Test ohne Parameter.
- Schreibe INFO/ERROR mit Test-Session und parse jede JSONL-Zeile mit `ConvertFrom-Json`.
- Redaction-Test mit Fake-Token.
- Paralleltest mit mindestens 3 Jobs und je 20 Events.
- Pruefe, dass ein RunStart und genau ein passendes RunEnd dieselbe Run-ID besitzen.

Akzeptanzkriterien:
- Jeder reale MAIN/SUB/PART-Lebenszyklus ist ueber IDs rekonstruierbar.
- Provider-Fallbacks sind ohne Rohprompt nachvollziehbar.
- JSONL bleibt auch bei Parallel-Jobs valide.
- Keine zweite konkurrierende Logimplementierung in `Vorce-Factory.ps1`.
- `Test-Logging.ps1`, `Test-Boot.ps1` und ein DryRun laufen ohne Loggingfehler.
```

### Prompt 5B - Bootstrap-, Prozess- und Terminal-Logging konkret verbessern

```text
Du bist Infrastruktur-Logging-Agent. Bearbeite den aktuellen Einstiegspunkt `Vorce-Factory/Start-Vorce-Factory.ps1`. Alte Namen nur dann anfassen, wenn ein Kompatibilitaets-Alias existiert.

Zu aendernde Dateien:
- `Vorce-Factory/Start-Vorce-Factory.ps1`
- `Vorce-Factory/Vorce-Factory.ps1`
- `Vorce-Factory/src/tools/services/sync-service.ps1`
- `Vorce-Factory/web/Dashboard/server/WebSocketServer.js`, nur falls dieser Dienst weiterhin gebraucht wird
- `Vorce-Factory/src/lib/logging/Write-Log.ps1`
- neu: `Vorce-Factory/test/Test-ProcessSupervisor.ps1`

Ziel:
Start, Health, Stop und Crash der Komponenten `dashboard`, `sync-service` und `factory-loop` muessen anhand von PID und Logs nachvollziehbar sein.

Teilaufgaben:

5B.1 - Prozessregistry
- Schreibe nach erfolgreichem Start `var/tmp/vorce-processes.json`.
- Pro Prozess:
  `{ component, pid, parent_pid, started_at, command_path, working_directory, port, health_url, stdout_path, stderr_path, session_id }`
- Schreibe atomar ueber temporaere Datei + Rename.
- Entferne Eintrag beim kontrollierten Stop.

5B.2 - Startausgabe
- Direkt nach Start eine kompakte Tabelle:
  - Komponente
  - PID
  - Port
  - Health
  - Logpfade
- Keine komplette CommandLine mit Secrets oder Promptargumenten ausgeben.

5B.3 - Healthchecks
- Dashboard: `/api/health` auf Port 5173.
- Sync: eigener Health-Endpunkt auf Port 5174, falls der Dienst dort lauscht.
- Factory-Loop: Prozess lebt und aktualisiert optional `var/tmp/factory-heartbeat.json`.
- Health-Wartezeit und Pollingintervall konfigurierbar, Default 60 Sekunden / 1 Sekunde.

5B.4 - Laufende Statusanzeige
- Im Vordergrundmodus alle 10 Sekunden oder nur bei Zustandsaenderung eine einzelne kompakte Statuszeile.
- Kein dauerndes Wiederholen der letzten Logzeile.
- Status: `healthy`, `starting`, `degraded`, `stopped`.
- Bei `-Detach` nach erfolgreicher Starttabelle sauber beenden.

5B.5 - Crashdiagnose
- Bei unerwartetem Exit:
  - ExitCode
  - letzte 30 nichtleere stdout-Zeilen
  - letzte 30 nichtleere stderr-Zeilen
  - Pfade zu beiden Dateien
- Terminalauszug auf maximal 60 Zeilen begrenzen.
- Vollstaendige Diagnose als Fehler-Event und optional Artefakt.

5B.6 - Sichere Stoplogik
- Zuerst PIDs aus `vorce-processes.json` verwenden.
- Vor Stop pruefen, ob CommandPath/WorkingDirectory noch zur erwarteten Komponente passt.
- Portbasierter Fallback nur fuer 5173/5174 und nie System-PID <= 4.
- Keine breiten Regex wie nur `vite`, `dashboard` oder `autopilot`.

5B.7 - Fehler bei Abhaengigkeiten
- Fehlendes `npm`, `pwsh`/`powershell`, Node-Module oder Script mit konkreter Meldung abbrechen.
- `npm install` ExitCode pruefen.
- Kein stilles Weiterlaufen nach fehlgeschlagenem Dashboard- oder Sync-Start.

5B.8 - Tests
- Teste Registry schreiben/lesen mit Fake-Prozessen.
- Teste, dass fremde PIDs nicht gestoppt werden.
- Teste Crashauszug mit Fixture-Logs.
- Manueller Smoke:
  `.\Start-Vorce-Factory.ps1 -NoAutopilot -Detach`

Akzeptanzkriterien:
- Jede gestartete Komponente ist mit PID, Health und Logpfad sichtbar.
- Stop/Restart arbeitet primaer PID-basiert.
- Startfehler enthalten die konkrete stderr-Ursache.
- Terminal bleibt kompakt und Logs bleiben vollstaendig.
```

### Prompt 5C - Dashboard-Live-Log entfernen und durch letzte Run-Zusammenfassungen ersetzen

```text
Du bist Dashboard-Statistik-Agent. Das Dashboard benoetigt keine Live-Log-Ansicht mehr. Entferne die Live-Log-Abhaengigkeit aus der Hauptansicht und zeige stattdessen kurze Zusammenfassungen und Statistikwerte der letzten Runs.

Zu aendernde Dateien:
- `Vorce-Factory/web/Dashboard/src/App.tsx`
- `Vorce-Factory/web/Dashboard/src/pages/DashboardPage.tsx`
- `Vorce-Factory/web/Dashboard/src/components/LiveLogMonitor.tsx`
- `Vorce-Factory/web/Dashboard/src/hooks/useWebSocketEnhanced.ts`
- `Vorce-Factory/web/Dashboard/src/types.ts`
- `Vorce-Factory/web/Dashboard/vite.config.ts`
- `Vorce-Factory/src/lib/state/StateManager.ps1`
- Datenquelle aus Punkt 4C: `Vorce-Factory/var/run-history/**`

Ziel:
Keine scrollende Logtabelle und kein Live-Log-WebSocket im Dashboard. Stattdessen:
1. Zusammenfassung der letzten 10 MAIN-RUN-Ausfuehrungen.
2. Aggregierte Werte fuer letzte 24 Stunden und letzte 7 Tage.
3. Kurze Hinweise auf Fehler, Fallbacks und wiederverwendete Checkpoints.

Teilaufgaben:

5C.1 - Neue API
- Implementiere `GET /run-summary.json`.
- Quelle ist Run-History, nicht Textparsing aus `autopilot-service.log`.
- Query optional: `?limit=10`.
- Bei fehlender History leeres, valides Objekt liefern.

Vertrag:

{
  "generated_at": "...",
  "recent_runs": [
    {
      "run_id": "...",
      "main_run": "MAIN-RUN-01_Planning",
      "status": "completed|failed|waiting_provider",
      "started_at": "...",
      "completed_at": "...",
      "duration_ms": 0,
      "sub_runs": { "completed": 0, "failed": 0, "skipped": 0, "reused": 0 },
      "part_runs": { "completed": 0, "failed": 0, "skipped": 0, "reused": 0 },
      "provider_attempts": 0,
      "fallbacks": 0,
      "estimated_cost_usd": 0,
      "input_tokens": 0,
      "output_tokens": 0,
      "result_summary": "maximal 160 Zeichen",
      "primary_error": null
    }
  ],
  "stats_24h": {},
  "stats_7d": {}
}

5C.2 - Statistikfelder
- Anzahl gestartete/abgeschlossene/fehlgeschlagene MAIN-RUNs.
- Erfolgsquote.
- Durchschnitts- und P95-Laufzeit.
- Anzahl SUB-/PART-RUNs completed/failed/skipped/reused.
- Provider-Versuche und Fallback-Anzahl.
- RateLimit-/Timeout-/Auth-Fehler.
- Kosten und Tokens, soweit Provider Daten liefern.
- `no_work` Ergebnisse getrennt von Fehlern.

5C.3 - UI
- Ersetze `LiveLogMonitor` auf `DashboardPage.tsx` durch:
  - Tabelle "Letzte Runs" mit Zeit, Run, Status, Dauer, Parts, Fallbacks.
  - kleine KPI-Zeile "24h: Erfolgsquote, Runs, Fallbacks, durchschnittliche Dauer".
- Klick auf einen Run zeigt kompakte Details aus dem State, nicht Rohlogs.
- Maximal 10 Zeilen, keine Auto-Scroll-Logik.

5C.4 - Live-Log-Code entkoppeln
- Entferne Fetch/Polling fuer `/live-log.json` aus `App.tsx`, sofern keine andere Seite es nutzt.
- Entferne `LiveLogMonitor` Import und Rendering.
- Entferne nur ungenutzte Live-Log-Hooks. WebSocket-Sync fuer andere Daten darf bleiben.
- Die Textlogs und `/api/live-log` duerfen fuer technische Diagnose vorerst bestehen, sind aber keine Dashboard-Abhaengigkeit.

5C.5 - Typen und Tests
- Definiere `RunSummary`, `RecentRunSummary`, `RunWindowStats`.
- Fuege einen Typecheck-Script hinzu, z.B. `tsc --noEmit`, und lasse ihn vor dem Build laufen.
- API-Fixtures fuer completed, failed, waiting_provider und reused.

Akzeptanzkriterien:
- Dashboard zeigt keine Live-Log-Komponente mehr.
- Letzte 10 Runs und 24h-/7d-Statistiken sind ohne Textlog-Parsing sichtbar.
- Ein Provider-Fallback und ein wiederverwendeter PART-RUN sind in der Zusammenfassung zaehlbar.
- `npm run typecheck` und `npm run build` erfolgreich.
```

## Punkt 6: Provider-Fallback mit Checkpoint/Resume korrekt implementieren

Status: [TEILWEISE] Provider-Runner und Fallback-Basis sind vorbereitet, Resume und Wiederverwendung sind noch nicht abgenommen.

### Prompt 6A - Registry-getriebenen Provider-Runner und Fallback-Kette bauen

```text
Du bist AgentRunner-/Fallback-Agent. Implementiere zuerst den zentralen Provider-Runner. Veraendere noch keine fachlichen Run-Prompts, bevor die Tests fuer den Runner bestehen.

Zu aendernde Dateien:
- `Vorce-Factory/src/lib/integrations/AgentRunner.ps1`
- `Vorce-Factory/src/lib/engines/QuotaManager.ps1`
- `Vorce-Factory/var/config/quota-registry.json`
- `Vorce-Factory/var/config/autopilot-config.json`
- neu: `Vorce-Factory/test/Test-AgentRunner.ps1`

Aktuell konfigurierte Provider:
- CLI: `gemini_cli`, `claude_code`, `codex_orchestrator`, `kiro_cli`, `cline_cli`, `copilot_cli`, `cursor_agent`
- Non-CLI: `jules`
- Nicht konfigurierte Namen wie `hermes_cli`, `jules_cli`, `jules_extern` duerfen nicht still erfunden werden.

Teilaufgaben:

6A.1 - Registry-Adapter
- Implementiere `Get-VorceProviderDefinition`.
- Nutze `command`, `cli_args`, `models`, `enabled`, `auth_env_var`.
- Ersetze `{PROMPT}` und `{MODEL}` ohne Shell-String-Evaluation.
- Args bleiben String-Array.

6A.2 - Prompttransport
- Provider-Definition erhaelt optional `prompt_transport = argument|stdin|tempfile`.
- Default:
  - kurze Prompts duerfen als Argument laufen, wenn Registry dies verlangt.
  - lange Prompts ab konfigurierbarer Grenze, Default 6000 Zeichen, muessen stdin oder Tempfile verwenden.
- Tempdatei unter `var/tmp/agent-artifacts/<main_run_id>/<part_run_id>/<attempt_id>/`.

6A.3 - Prozessausfuehrung
- Command mit `Get-Command` aufloesen.
- WorkingDirectory explizit.
- Timeout implementieren; Prozessbaum bei Timeout gezielt beenden.
- stdout und stderr getrennt erfassen.
- Headless-/Noninteractive-Flags ausschliesslich aus Registry.

6A.4 - Einzelversuch-Ergebnis

{
  "success": false,
  "provider": "gemini_cli",
  "model_tier": "balanced",
  "model": "...",
  "attempt_id": "...",
  "exit_code": 1,
  "duration_ms": 0,
  "output": "",
  "stdout_path": "...",
  "stderr_path": "...",
  "error_class": "timeout",
  "retryable": true,
  "fallback_recommended": true
}

6A.5 - Fallback-Funktion
- Implementiere:
  `Invoke-VorceAgentWithFallback -TaskType -Prompt -PreferredChain -RunContext -ExpectedOutput`.
- Reihenfolge:
  1. explizite `PreferredChain`
  2. `quota-registry.routing_rules.<TaskType>`
  3. task-spezifische `run_settings.part_runs.<name>.llm_chain`
  4. konservativer Default aus aktivierten CLI-Providern
- Duplikate normalisieren und entfernen.
- `jules` fuer CLI-Aufruf mit `unsupported_for_cli` skippen.

6A.6 - Skip-/Fallback-Gruende
- `disabled`
- `unknown_provider`
- `unsupported_for_cli`
- `command_missing`
- `auth_missing`
- `quota_exhausted`
- `rate_limited`
- `timeout`
- `exit_nonzero`
- `empty_output`
- `invalid_output`
- `policy_blocked`

6A.7 - Quota
- `attempted_calls` nach realem Prozessstart erhoehen.
- Erfolgreiche/abrechenbare Nutzung getrennt erfassen.
- Kein Usage-Increment bei `command_missing`, `disabled` oder `quota_exhausted`.

6A.8 - Chain erschoepft
- Nicht 15 Minuten blockierend innerhalb des PART-RUNs schlafen.
- Ergebnis `status=waiting_provider`, `retry_after=(now+15min)`, `resume_required=true`.
- Orchestrator aus Punkt 6C setzt denselben MAIN-RUN spaeter fort.
- Config:
  `fallback.retry_after_minutes = 15`
  `fallback.max_chain_cycles = 3`
- Nach maximalen Zyklen final `failed`, ausser User setzt manuell fort.

6A.9 - Tests
- Fake-CLI-Fixtures fuer success, exit 1, timeout, leeren Output und invalid JSON.
- Teste Chain `missing -> timeout -> success`.
- Teste, dass Jules geskippt wird.
- Teste Quota-Zaehlung.
- Keine echten kostenpflichtigen Provider im Unit-Test.

Akzeptanzkriterien:
- Alle aktuell konfigurierten Provider werden ausgefuehrt oder mit einem exakten Grund geskippt.
- Kein `Unbekannter Agent` Crash.
- Keine blockierende 15-Minuten-Wartezeit im Worker.
- Ergebnisobjekt und Attempts sind vollstaendig.
```

### Prompt 6B - Deliberation und alle LLM-PART-RUNs an Fallback anschliessen

```text
Du bist Deliberation-/Routing-Agent. Verwende den in 6A getesteten Runner in allen fachlichen LLM-Aufrufen.

Zu aendernde Dateien:
- `Vorce-Factory/src/lib/engines/DeliberationEngine.ps1`
- `Vorce-Factory/src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/PART-RUNS/PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1`
- weitere Treffer aus:
  `rg -n "Invoke-VorceAgent|gemini_cli|claude_code" Vorce-Factory/src -g "*.ps1"`
- `Vorce-Factory/var/config/autopilot-config.json`
- `Vorce-Factory/var/prompts/shared/deliberation/**`
- neu: `Vorce-Factory/test/Test-DeliberationFallback.ps1`

Teilaufgaben:
1. Proposal nutzt `dual_ceo.ceo_chain`, danach `routing_rules.planning`.
2. Critique nutzt `dual_ceo.qa_manager_chain`, danach `routing_rules.audit`.
3. Synthesis nutzt CEO-Chain; der bereits erfolgreiche Critique-Provider darf als spaeter Fallback vorkommen.
4. Jede Phase erhaelt eine eigene `phase_id`, bleibt aber im selben PART-/MAIN-Run-Kontext.
5. Phasenresultat speichert Provider, Modell, Dauer, Attempts, Output-Validierung und Artefaktpfad.
6. `fallback_to_single=true`:
   - Proposal erfolgreich, Critique nicht verfuegbar: Ergebnis darf `single_agent_fallback` sein.
   - Proposal selbst fehlgeschlagen: kein fachlich gueltiges Ergebnis vortaeuschen.
7. `waiting_provider` muss an RunEngine/Orchestrator weitergegeben werden und darf nicht als `completed` gespeichert werden.
8. Vollstaendige LLM-Ausgaben nicht in Main-State kopieren. State enthaelt Summary und Artefaktreferenz.

Akzeptanzkriterien:
- Kein harter Gemini-only Aufruf bleibt.
- Deliberation-Historie zeigt jede Phase und jeden Fallbackversuch.
- `no_work` bleibt ein valides Ergebnis und loest keinen Provider-Fallback aus.
- Tests decken Proposal-Erfolg, Critique-Fallback, Chain-Exhaustion und Resume ab.
```

### Prompt 6C - Unfertigen MAIN-RUN nach Provider-Fallback fortsetzen, ohne fertige Runs zu wiederholen

```text
Du bist Checkpoint-/Resume-Agent. Implementiere eine einfache, sichere Wiederaufnahme innerhalb desselben nicht abgeschlossenen MAIN-RUNs.

Zu aendernde Dateien:
- `Vorce-Factory/src/lib/state/StateManager.ps1`
- `Vorce-Factory/src/lib/engines/RunEngine.ps1`
- `Vorce-Factory/src/orchestrator/Vorce-Orchestrator.ps1`
- `Vorce-Factory/Vorce-Factory.ps1`
- `Vorce-Factory/src/lib/integrations/AgentRunner.ps1`
- optional `Vorce-Factory/var/config/autopilot-config.json`
- neu: `Vorce-Factory/test/Test-MainRunResume.ps1`

Ziel:
Wenn ein Provider innerhalb eines PART-RUNs ausfaellt oder die komplette Chain voruebergehend nicht verfuegbar ist, darf nicht der gesamte MAIN-RUN neu beginnen. Alle bereits erfolgreich erfassten SUB-/PART-Ergebnisse desselben MAIN-RUNs muessen weiterverwendet werden.

Verbindliche Regeln:

1. Ein Resume behaelt dieselbe `main_run_id`.
2. Ein bereits `completed` PART-RUN wird nicht erneut ausgefuehrt, wenn:
   - Parent-MAIN-RUN identisch ist,
   - `input_fingerprint` identisch ist,
   - alle Abhaengigkeiten noch dieselben Ergebnis-IDs besitzen,
   - das Ergebnis als `reusable=true` markiert ist.
3. Ein PART-RUN mit `failed` wird nur erneut versucht, wenn Fehlerklasse retryable ist.
4. Ein PART-RUN mit `waiting_provider` setzt beim naechsten noch nicht versuchten Provider bzw. Chain-Zyklus fort.
5. Ein SUB-RUN gilt nur als wiederverwendbar, wenn alle benoetigten PART-RUNs completed/reused sind.
6. Router wird beim Resume nur fuer Diagnose erneut ausgewertet. Bereits abgeschlossene aktive Runs bleiben abgeschlossen; neue Routerentscheidungen duerfen fertige Resultate nicht loeschen.

Zu speichernde Checkpoint-Daten:

{
  "resume": {
    "resume_count": 1,
    "last_checkpoint_at": "...",
    "retry_after": "...",
    "blocked_part_run": "...",
    "reason": "provider_chain_exhausted"
  },
  "execution_graph": [
    {
      "run_name": "...",
      "type": "SUB|PART",
      "status": "completed|waiting_provider|failed|skipped",
      "input_fingerprint": "...",
      "dependency_result_ids": [],
      "result_ref": "...",
      "reusable": true,
      "attempts": []
    }
  ]
}

Teilaufgaben:

6C.1 - Fingerprints
- Erzeuge SHA-256 aus kanonisch serialisierten fachlichen Inputs, nicht aus Timestamp oder Providername.
- Beispiele:
  - Fetch/Triage: Repo + Snapshot-ID + Filterconfig.
  - Strategy: IDs/Hashes der triagierten Issues + Prompt-Version.
  - Deliberation-Phase: Prompt-ID + Variablenhash + vorherige Phasenresultat-ID.

6C.2 - Result-Referenzen
- Grosse Ergebnisse als Artefakt/History-Datei speichern.
- Main-State enthaelt `result_ref`, kurze Summary und Ergebnis-ID.
- Beim Resume ParentState aus den referenzierten Ergebnissen rehydrieren, z.B. `performance_data`, DataSync-Snapshot, Triage-Ergebnis oder Proposal.

6C.3 - Ausfuehrungslogik
- Vor jedem PART-RUN `Get-VorceReusableRunResult` aufrufen.
- Bei Treffer:
  - Script nicht ausfuehren.
  - State-Event `run_reused`.
  - Aggregatstatus fuer diesen Part `reused`.
- Bei keinem Treffer normal ausfuehren.

6C.4 - Providerwechsel innerhalb desselben Parts
- Vorherige Provider-Attempts bleiben am PART-State.
- Neuer Provider bekommt denselben fachlichen Prompt/Input.
- Ein erfolgreicher Fallback schliesst nur den blockierten PART-RUN ab; danach laeuft der naechste offene PART-/SUB-RUN weiter.

6C.5 - Prozessneustart
- `Vorce-Factory.ps1` prueft vor Auswahl eines neuen MAIN-RUNs auf `waiting_provider` oder `running` ohne aktiven Prozess.
- Wenn `retry_after` erreicht ist, denselben MAIN-RUN mit `-ResumeRunId` fortsetzen.
- Unfertige Runs haben Vorrang vor neu faelligen normalen Runs, ausser sie sind manuell pausiert.

6C.6 - Seiteneffekte idempotent machen
- Parts wie Issue-Erstellung oder Delegation brauchen `idempotency_key`.
- Vor erneutem Seiteneffekt pruefen, ob bereits ein Resultat/Issue mit diesem Key existiert.
- Ein Resume darf keine doppelten Issues, Delegationen oder Kommentare erzeugen.

6C.7 - Invalidation
- Wiederverwendung ablehnen bei geaendertem Input-Fingerprint, fehlendem Artefakt, geaenderter Prompt-Version oder explizitem `-ForceRecompute`.
- Ablehnung mit Reason loggen.

6C.8 - Tests
- Fixture-MAIN-RUN mit 3 Parts:
  - Part 1 completed
  - Part 2 completed
  - Part 3 Provider A fehlgeschlagen, Provider B spaeter erfolgreich
- Assert: Part 1 und 2 wurden genau einmal ausgefuehrt, Part 3 besitzt zwei Attempts, Main endet completed.
- Teste kompletten Prozessneustart zwischen Attempts.
- Teste geaenderten Fingerprint: betroffener Part und davon abhaengige Parts werden neu ausgefuehrt.
- Teste idempotenten Side-Effect-Part.

Akzeptanzkriterien:
- Kein bereits gueltig abgeschlossener SUB-/PART-RUN wird wegen Provider-Fallback erneut ausgefuehrt.
- Derselbe Main-Run kann nach 15 Minuten oder Prozessneustart fortgesetzt werden.
- Dashboard-Statistik kann `reused` und `resume_count` anzeigen.
- Keine doppelten externen Seiteneffekte.
```

## Punkt 7: LLM-/CLI-Aufrufe testen, absichern und Ergebnisse validieren

Status: [OFFEN] Testabdeckung fuer Provider-, CLI- und Output-Verhalten ist noch nicht vollstaendig vorhanden.

### Prompt 7A - Provider-Test-Suite mit Discovery, DryRun, FakeCLI und optionalem Smoke

```text
Du bist CLI-Test-Agent. Erstelle `Vorce-Factory/test/Test-LLMProviders.ps1`. Der Defaultmodus darf keine kostenpflichtigen echten Calls ausfuehren.

Modi:
- `-DiscoveryOnly`: Registry, Command, Modell und Argumenttemplate pruefen.
- `-DryRun`: finale Command-/Arg-Struktur bauen, aber nicht starten.
- `-FakeCli`: lokale Fixture-Executables fuer Erfolg/Fehler/Timeout verwenden.
- `-Smoke`: echter kurzer Call nur mit zusaetzlichem `-AllowPaidCalls`.

Teilaufgaben:
1. Iteriere dynamisch ueber alle `quota-registry.providers`.
2. Markiere `jules` als `non_cli`.
3. Entferne Hardcoding aus `Test-StartProcess.ps1`; Datei entweder auf neuen Test umleiten oder archivieren.
4. Pro Provider ausgeben:
   `{ provider, kind, enabled, optional, command, command_found, models_valid, args_valid, prompt_transport, headless_flags_present, discovery_status }`
5. FakeCLI testet stdout, stderr, ExitCode, Timeout, Promptdatei und Cleanup.
6. Smoke-Prompt: `Return exactly OK`.
7. Smoke timeout Default 60 Sekunden.
8. Echte Smoke-Ergebnisse ohne kompletten Output speichern.
9. Enabled + nicht optional + Command fehlt => Testfehler.

Akzeptanzkriterien:
- Alle Registry-Provider erscheinen genau einmal.
- Defaulttest ist kostenfrei.
- Runner und Test verwenden denselben Command-Builder.
- Fehlende Tools und ungueltige Args sind klar diagnostiziert.
```

### Prompt 7B - Direkte Prozess-/CLI-Aufrufe gezielt migrieren

```text
Du bist CLI-Aufruf-Audit-Agent. Suche repo-weit und behebe konkrete direkte Aufrufe.

Pflichtsuche:
`rg -n "Start-Process|execSync|spawnSync|\\bgh\\b|\\bgemini\\b|\\bclaude\\b|\\bcodex\\b|\\bkiro\\b|\\bcline\\b|\\bcopilot\\b|cursor-agent" Vorce-Factory .github scripts`

Bekannte konkrete Stellen:
- `src/lib/integrations/AgentRunner.ps1`
- `test/Test-StartProcess.ps1`
- `src/runs/MAIN-RUN-01_Planning/...CreateDelegations.ps1`
- `src/runs/MAIN-RUN-02_CheckAndDoing/CheckAndDoing-Router.ps1`
- `src/runs/MAIN-RUN-02_CheckAndDoing/...DispatchReviews.ps1`
- `src/runs/MAIN-RUN-02_CheckAndDoing/...RefillJulesQueue.ps1`
- `web/Dashboard/vite.config.ts` bei `gh`-Schreiboperationen
- Bootstrap-Prozessstarts in `Start-Vorce-Factory.ps1`

Regeln:
1. LLM-Provider nur ueber AgentRunner.
2. GitHub-CLI ueber zentrale PowerShell-/Node-Helper mit Argumentarray.
3. Keine interpolierten Shellstrings fuer Titel, Body, Labels, Repo oder Usertext.
4. ExitCode, stdout, stderr und Timeout immer pruefen.
5. Headless-Flags kommen aus Registry.
6. Prompts nicht in Prozessliste oder Logs sichtbar machen, wenn stdin/Tempfile moeglich ist.
7. Dashboard Node-Code nutzt `spawnSync`/`execFileSync`, nicht `execSync` mit zusammengebautem String.
8. Jeder direkte Aufruf wird klassifiziert: `allowed_bootstrap`, `github_helper`, `provider_runner`, `must_migrate`.

Deliverables:
- Audit-Tabelle Datei/Zeile/Klassifikation/Fix.
- Keine offenen `must_migrate` Treffer.
- Tests: Provider Discovery/FakeCLI, Dashboard Typecheck/Build, relevante Run-Tests.
```

### Prompt 7C - Output-Schema und Fehlerklassifizierung pro Task erzwingen

```text
Du bist LLM-Result-Validation-Agent. Implementiere Validierung zwischen AgentRunner und fachlichen Runs.

Zu aendernde Dateien:
- `src/lib/integrations/AgentRunner.ps1`
- neu oder passend: `src/lib/integrations/AgentResultValidator.ps1`
- `src/lib/engines/DeliberationEngine.ps1`
- LLM-verarbeitende PART-RUNs
- Tests: `test/Test-AgentResultValidation.ps1`

Fehlerklassen:
- `command_missing`
- `auth_missing`
- `quota_exhausted`
- `rate_limited`
- `timeout`
- `exit_nonzero`
- `empty_output`
- `invalid_json`
- `schema_mismatch`
- `policy_blocked`
- `artifact_missing`
- `unknown_provider_error`

Fachlich gueltige Nicht-Fehler:
- `no_work`
- `no_changes`
- `no_prs`
- `no_delegations`
- `insufficient_data`

Teilaufgaben:
1. `ExpectedOutput` unterstuetzt `text`, `json`, `json_schema`, `exact`.
2. Markdown-Codefences vor JSON-Parse entfernen, aber keine beliebige Textreparatur erfinden.
3. JSON-Schema pro Task klein und explizit definieren.
4. Pflichtfelder und Typen pruefen.
5. Provider-Wrapper-JSON von fachlichem Output trennen.
6. Typische Auth/RateLimit/Policy-Muster aus stderr/stdout klassifizieren.
7. `retryable` und `fallback_recommended` anhand Fehlerklasse setzen.
8. Rohoutput nur bei Fehler/Debug als Artefakt; Erfolgsstate nur Summary und Hash.
9. Kein Fallback bei gueltigem `no_work`.

Akzeptanzkriterien:
- Fachliche Leere und technischer Fehler sind unterscheidbar.
- Invalid JSON loest Fallback oder strukturierten Fehler aus.
- Keine kompletten langen Outputs im Terminal oder Main-State.
- Fixture-Tests fuer jede Fehlerklasse und alle Nicht-Fehler.
```

## Punkt 8: Provider-Namen und Aufbewahrung konsistent machen

Status: [TEILWEISE] Normalisierung und Rotation sind als Ziel definiert, aber noch nicht flaechenweit konsistent umgesetzt.

### Prompt 8A - Provider-IDs zentral normalisieren

```text
Du bist Quota-Normalisierungs-Agent. Implementiere eine einzige Normalisierungsfunktion und migriere konkrete falsche Aufrufer.

Zu aendernde Dateien:
- `Vorce-Factory/src/lib/engines/QuotaManager.ps1`
- `Vorce-Factory/src/lib/integrations/AgentRunner.ps1`
- `Vorce-Factory/src/runs/MAIN-RUN-02_CheckAndDoing/...DispatchReviews.ps1`
- alle Treffer fuer `Test-VorceQuota`, `Register-VorceQuotaUsage`, `Invoke-VorceAgent`
- `Vorce-Factory/test/Test-ProviderAliases.ps1`

Kanonische IDs:
- `gemini_cli`
- `claude_code`
- `codex_orchestrator`
- `kiro_cli`
- `cline_cli`
- `copilot_cli`
- `cursor_agent`
- `jules`

Erlaubte Legacy-Aliase:
- `gemini` -> `gemini_cli`
- `claude` -> `claude_code`
- `codex`, `codex_cli` -> `codex_orchestrator`
- `kiro` -> `kiro_cli`
- `cline` -> `cline_cli`
- `copilot` -> `copilot_cli`
- `cursor`, `cursor-agent` -> `cursor_agent`
- `jules_cli`, `jules_extern` -> `jules`

Teilaufgaben:
1. `Resolve-VorceProviderId` ist die einzige Alias-Map.
2. QuotaManager und AgentRunner rufen sie am Eingang auf.
3. Registry speichert nur kanonische IDs.
4. Legacy-Alias erzeugt einmal pro Session WARN-Event, nicht bei jedem Call.
5. Unbekannter Alias liefert strukturiert `unknown_provider`.
6. `DispatchReviews.ps1` darf nicht mehr `claude`/`gemini` an QuotaManager uebergeben.
7. Dashboard zeigt kanonische ID plus lesbares Label.
8. `hermes_cli` nur aufnehmen, wenn ein realer Registry-Eintrag mit Command/Args existiert.

Akzeptanzkriterien:
- Keine Quota-Pruefung scheitert nur am Alias.
- Keine doppelte Alias-Map.
- Tests pruefen alle oben genannten Aliase und einen unbekannten Namen.
```

### Prompt 8B - Rotation fuer Events, Session-Logs, Fehler und Artefakte

```text
Du bist Log-Hygiene-Agent. Implementiere Rotation nach dem neuen Loggingmodell aus 5A. Dashboard-Live-Log ist kein Ziel mehr.

Zu aendernde Dateien:
- `Vorce-Factory/src/lib/logging/Write-Log.ps1`
- neu oder passend: `Vorce-Factory/src/lib/logging/LogMaintenance.ps1`
- `Vorce-Factory/Vorce-Factory.ps1`
- `Vorce-Factory/Start-Vorce-Factory.ps1`
- Housekeeping-PART-RUN
- neu: `Vorce-Factory/test/Test-LogRetention.ps1`

Retention-Defaults:
- JSONL Events: 30 Tage, gzip nach 2 Tagen.
- Session-Textlogs: letzte 30 Dateien und maximal 30 Tage.
- `vorce-errors.log`: rotieren bei 10 MB, maximal 5 Generationen.
- stdout/stderr Prozesslogs: 14 Tage.
- Agent-Artefakte erfolgreicher Attempts: 24 Stunden.
- Agent-Artefakte fehlgeschlagener Attempts: 7 Tage.
- Run-History: nicht durch Log-Cleanup loeschen; separate spaetere Policy.
- Config-Backups: letzte 20.

Sicherheitsregeln:
1. Aktive Dateien anhand aktueller `session_id`, offener Filehandles oder Prozessregistry nicht loeschen.
2. Cleanup mit `-WhatIf`/DryRun-Modus.
3. Jeder Delete/Compress als `cleanup` Event mit Pfadkategorie und Anzahl, aber ohne riesige Dateiliste.
4. Fehler im Cleanup sind WARN und brechen den MAIN-RUN nicht.
5. Keine `var/run-states`, `var/run-history`, `var/db` oder Config-Dateien loeschen.
6. Keine rekursive Loeschung ausserhalb explizit erlaubter Rootpfade.

Tests:
- Temp-Fixtures mit altem/neuem Datum und Groesse.
- Aktive Datei bleibt erhalten.
- DryRun veraendert nichts.
- Pfad ausserhalb erlaubter Roots wird abgelehnt.

Akzeptanzkriterien:
- Logs/Artefakte wachsen begrenzt.
- Aktive oder fachliche State-Daten bleiben unangetastet.
- Rotation ist testbar und nachvollziehbar.
```

## Punkt 9: Optimizer und MemoryOptimization sinnvoll in kleine, kostenguenstige PART-RUNs aufteilen

Status: [OFFEN] Die Zielstruktur ist beschrieben, aber die feingranulare Aufteilung und Reuse-Logik fehlen noch.

Grundprinzip:

- Ein PART-RUN ist eine kleine, wiederaufnehmbare Arbeitseinheit mit eigenem State und Input-Fingerprint.
- Nicht jeder PART-RUN startet ein LLM. Datensammlung, Filterung, Scoring, Deduplizierung und Reporting sollen lokal/deterministisch laufen.
- Ein LLM wird nur fuer die wenigen Schritte verwendet, bei denen Text-/Codebewertung einen klaren Mehrwert hat.
- Jeder LLM-PART-RUN bekommt begrenzten Input, Output-Schema, Tokenbudget und Fallback-Resume.
- SUB-RUNs werden nur aktiv, wenn ihre Inputs vorhanden sind. Keine leeren Sessions.

Verbindliche Zieltopologie fuer `MAIN-RUN-04_Optimizer`:

1. `SUB-RUN-01_MR-04_Optimizer__PerformanceDataCollection`
   - `PART-RUN-01_...__CollectRunMetrics`
   - `PART-RUN-02_...__CollectProviderAndFallbackMetrics`
   - `PART-RUN-03_...__BuildMetricsSnapshot`
2. `SUB-RUN-02_MR-04_Optimizer__SystemAnalysis`
   - `PART-RUN-01_...__DetectRunBottlenecks`
   - `PART-RUN-02_...__DetectRoutingAndPromptWaste`
3. `SUB-RUN-03_MR-04_Optimizer__ProposalGeneration`
   - `PART-RUN-01_...__BuildCandidateProposals`
   - `PART-RUN-02_...__RefineTopProposalsWithLLM`
4. `SUB-RUN-04_MR-04_Optimizer__ApprovedChangeDispatch`
   - `PART-RUN-01_...__ValidateApprovedChanges`
   - `PART-RUN-02_...__ApplyLowRiskConfigChanges`
   - `PART-RUN-03_...__CreateIssuesForCodeChanges`
5. `SUB-RUN-05_MR-04_Optimizer__ChangeEvaluation`
   - `PART-RUN-01_...__CompareBeforeAfterMetrics`
   - `PART-RUN-02_...__ClassifyChangeOutcome`

Nur `RefineTopProposalsWithLLM` ist standardmaessig ein LLM-Part. Alle anderen Parts sind lokal, ausser spaeter explizit anders freigegeben.

Verbindliche Zieltopologie fuer `MAIN-RUN-05_MemoryOptimization`:

1. `SUB-RUN-01_MR-05_MemoryOptimization__MemoryInventory`
   - `PART-RUN-01_...__LoadAndNormalizeMemories`
   - `PART-RUN-02_...__DetectExpiredDuplicateAndInvalidMemories`
2. `SUB-RUN-02_MR-05_MemoryOptimization__MemorySelectionPolicy`
   - `PART-RUN-01_...__ScoreMemoryRelevance`
   - `PART-RUN-02_...__ValidateMemoryBudgets`
3. `SUB-RUN-03_MR-05_MemoryOptimization__MemoryMaintenance`
   - `PART-RUN-01_...__BuildMaintenancePlan`
   - `PART-RUN-02_...__ApplyApprovedMaintenance`
4. `SUB-RUN-04_MR-05_MemoryOptimization__MasterIssueContext`
   - `PART-RUN-01_...__SyncIssueRelationships`
   - `PART-RUN-02_...__UpdateChangedMasterIssueSummaries`
5. `SUB-RUN-05_MR-05_MemoryOptimization__MemoryReporting`
   - `PART-RUN-01_...__BuildMemoryUsageStatistics`

Nur `UpdateChangedMasterIssueSummaries` darf bedingt ein LLM verwenden. Alle anderen Memory-Parts sind lokal.

Nach vollstaendiger Umsetzung von Punkt 9 muss das Topologie-Manifest aus 4A bewusst von aktuell 5 MAIN / 17 SUB / 18 PART auf 5 MAIN / 24 SUB / 36 PART aktualisiert werden.

### Prompt 9A - Metrikdatenvertrag und lokale Performance-Sammlung implementieren

```text
Du bist Optimizer-Metrics-Agent. Teile den bisherigen grossen `CollectPerformanceMetrics` Part entsprechend der Zieltopologie auf.

Zu aendernde/neu anzulegende Dateien:
- bestehender SUB-RUN-01 Ordner unter `MAIN-RUN-04_Optimizer`
- drei neue PART-RUN-Dateien gemaess Zieltopologie
- bestehende `CollectPerformanceMetrics.ps1` nach erfolgreicher Migration entfernen oder als klaren Kompatibilitaets-Wrapper belassen
- `var/db/optimizer-metrics.json`
- Tests: `test/Test-OptimizerMetrics.ps1`

Part 01 `CollectRunMetrics`:
- Liest Run-History aus Punkt 4C.
- Erfasst je MAIN/SUB/PART:
  Dauer, Status, Fehlerklasse, skipped/reused, no_work, input_fingerprint.
- Keine Empfehlungen erzeugen.
- Keine LLM-Aufrufe.

Part 02 `CollectProviderAndFallbackMetrics`:
- Liest Provider-Attempts aus Run-State/Event-History und Quota-Registry.
- Erfasst Calls, Attempts, Fallbacks, Timeouts, RateLimits, Auth-Fehler, Tokens, Kosten.
- Erfasst Memory-Nutzung pro Run, soweit vorhanden.
- Keine LLM-Aufrufe.

Part 03 `BuildMetricsSnapshot`:
- Fuehrt Part 01/02 plus Queue-/Durchsatzdaten zusammen.
- Schreibt genau einen Snapshot mit `snapshot_id`, Zeitraum und Datenqualitaet.
- Dedupliziert nach Run-ID.
- Berechnet keine erfundenen Uptime- oder Effizienzwerte.

Mindestmetriken:
- Laufzeit avg/p95 pro Run.
- Erfolgs-, Fehler-, no_work-, skipped- und reused-Rate.
- Aktivierungsfrequenz pro Routerregel.
- Ergebnisrate pro aktiviertem Run.
- Provider-Fallbackrate.
- Issues geplant/delegiert/abgeschlossen.
- PRs reviewed/merged/failed.

Akzeptanzkriterien:
- Alle 3 Parts sind separat wiederaufnehmbar.
- Kein LLM-Call.
- Keine Empfehlungen in der Collection-Phase.
- Snapshot enthaelt `sample_count` und `data_quality`.
```

### Prompt 9B - Optimizer-Sub-Runs 02 bis 05 und Router exakt anlegen

```text
Du bist Optimizer-Topologie-Agent. Implementiere die oben definierte 5-SUB-/12-PART-Struktur fuer MAIN-RUN-04.

Zu aendernde Dateien:
- `Optimizer-Router.ps1`
- `var/config/autopilot-config.json.router_rules.Optimizer`
- neue SUB-/PART-Ordner unter `MAIN-RUN-04_Optimizer/SUB-RUNS`
- Dashboard Run-Katalog/Hierarchie nur soweit noetig, damit Ordner automatisch erscheinen
- Topologie-Manifest aus 4A aktualisieren

Routerbedingungen:
- SUB 01 PerformanceDataCollection: immer aktiv.
- SUB 02 SystemAnalysis: aktiv bei mindestens 3 verwertbaren Samples.
- SUB 03 ProposalGeneration: aktiv, wenn SUB 02 mindestens einen Finding-Kandidaten liefert.
- SUB 04 ApprovedChangeDispatch: aktiv, wenn mindestens ein Proposal `approved` ist.
- SUB 05 ChangeEvaluation: aktiv, wenn eine angewendete Aenderung ihr Beobachtungsfenster erreicht hat.

Sub 02:
- Part 01 erkennt langsame/fehlerhafte Runs deterministisch.
- Part 02 erkennt Routerverschwendung, wiederholte no_work Runs und Prompt-/Provider-Symptome.
- Output ist eine Finding-Liste, noch keine Aktion.

Sub 03:
- Part 01 baut regelbasierte Kandidaten und dedupliziert offene Proposals.
- Part 02 bekommt maximal die 3 bestbewerteten Kandidaten und maximal die benoetigte Evidence. LLM liefert strukturierten konkreten Vorschlag, keinen allgemeinen Auditbericht.
- Wenn kein Kandidat vorhanden ist, Part 02 `skipped=no_candidates`.

Sub 04:
- Part 01 validiert Status, Ziel, Risiko, Backup und Rollback.
- Part 02 darf nur whitelisted Configwerte aendern.
- Part 03 erstellt fuer Code-/Prompt-/High-Risk-Aenderungen ein GitHub-Issue statt direkter Aenderung.

Sub 05:
- Part 01 vergleicht Baseline und Beobachtungsfenster.
- Part 02 klassifiziert `effective|neutral|regressed|insufficient_data`.
- Bei `regressed` nur Rollback-Vorschlag oder automatischer Rollback, wenn der urspruengliche Change explizit `auto_rollback=true` hatte.

Akzeptanzkriterien:
- Alle Ordner, Config-Regeln und Tests sind aktualisiert.
- Leere Sub-Runs werden vom Router nicht gestartet.
- Nur ein standardmaessiger LLM-Part.
- Jeder angewendete Change wird mindestens 3 passende Runs oder 7 Tage beobachtet, konfigurierbar.
```

### Prompt 9C - Restriktive Optimizer-Regeln mit IDs, Evidence und Guardrails

```text
Du bist Optimizer-Regelwerk-Agent. Lege Regeln in einer maschinenlesbaren Config ab, z.B. `var/config/optimizer-rules.json`.

Pflicht-Regel-IDs:
- `OPT-RUN-001`: p95 Laufzeit ueber Grenzwert bei mindestens 3 Samples.
- `OPT-RUN-002`: Fehlerquote ueber Grenzwert bei mindestens 3 Samples.
- `OPT-ROUTER-001`: mindestens 3 Aktivierungen, davon >=80 Prozent `no_work`.
- `OPT-ROUTER-002`: Arbeit vorhanden, aber Run wiederholt nicht aktiviert.
- `OPT-PROMPT-001`: mindestens 2 `invalid_json` in 5 Versuchen.
- `OPT-PROMPT-002`: wiederholt leere oder ueber Budget liegende Outputs.
- `OPT-PAR-001`: Parallelitaet senken bei Timeout/RateLimit/Fehlerquote.
- `OPT-PAR-002`: Parallelitaet erhoehen nur bei Backlog, stabiler Laufzeit, Fehlerquote <5 Prozent und Quota.
- `OPT-SPLIT-001`: Part aufteilen, wenn er mehrere unabhaengige Seiteneffekte/LLM-Aufgaben besitzt oder p95 deutlich zu hoch ist.
- `OPT-MERGE-001`: Parts zusammenlegen nur, wenn beide immer gemeinsam laufen, lokal sind und Checkpoint-Nutzen gering ist.

Proposal-Pflichtfelder:
`id, rule_id, created_at, status, category, risk, target, evidence, sample_count, problem, proposed_action, expected_impact, rollback, observation_window, auto_applicable`.

Guardrails:
- Prompt-/Codeaenderung nie automatisch.
- Routerdeaktivierung nie automatisch.
- Low-Risk Auto-Apply nur fuer whitelisted numerische Configwerte.
- Maximal 3 neue Proposals pro Lauf.
- Gleicher `rule_id+target` nicht doppelt offen.
- Cooldown 24 Stunden pro Target.

Akzeptanzkriterien:
- Kein Proposal ohne Rule-ID und Evidence.
- `insufficient_data` erzeugt kein Proposal.
- Grenzwerte sind konfigurierbar und validiert.
```

### Prompt 9D - Memory-Selector und Budgetpruefung als getrennte lokale Parts implementieren

```text
Du bist Memory-Selection-Agent. Implementiere die Ziel-SUB-RUNs 01 und 02 sowie die Laufzeitfunktion zur Memory-Auswahl.

Zu aendernde Dateien:
- `MAIN-RUN-05_MemoryOptimization/**`
- `var/db/autopilot-memories.json`
- `src/lib/utils/PromptManager.ps1`
- neu sinnvoll: `src/lib/utils/MemoryManager.ps1`
- `var/config/autopilot-config.json`
- Tests: `test/Test-MemorySelection.ps1`

Memory-Schema:
`id, text, summary, type, priority, scope, expires_at, created_at, updated_at, last_used_at, use_count, usefulness_score, max_tokens, source, status`.

Typen:
`permanent|project|run_scoped|master_issue|temporary|negative`.

SUB 01:
- Part 01 normalisiert Legacy-Memories, ohne Inhalte zu verlieren.
- Part 02 markiert expired, duplicate, invalid und unscoped. Noch nichts loeschen.

SUB 02:
- Part 01 `ScoreMemoryRelevance` bewertet nur anhand expliziter Scope-Treffer:
  exact part > exact sub > exact main > issue/master_issue > label/repo > critical global.
- Part 02 `ValidateMemoryBudgets` waehlt die hoechsten Scores innerhalb der Budgets.

Runtime-Funktion:
`Select-VorceRelevantMemories -RunContext -IssueContext -MaxItems -MaxTokens`

Defaults:
- maximal 3 Memories.
- maximal 500 Tokens.
- Master-Issue-Kontext maximal 800 Tokens, aber nur bei exakter Beziehung.
- `summary` statt Volltext.
- Default ist keine Memory.

PromptManager:
- Injiziert nur das Ergebnis der Auswahl.
- Loggt IDs, Auswahlgrund, Score und geschaetzte Tokens.
- Aktualisiert `last_used_at` und `use_count` erst bei tatsaechlicher Injektion.

Akzeptanzkriterien:
- Auswahl ist deterministisch und lokal.
- Keine globale ungefilterte Injektion.
- Budget wird nie ueberschritten.
- Keine Memory => kein zusaetzlicher Promptblock.
```

### Prompt 9E - Memory-Maintenance in Plan und Apply trennen

```text
Du bist Memory-Maintenance-Agent. Implementiere SUB-RUN-03 mit zwei klar getrennten Parts.

Part 01 `BuildMaintenancePlan`:
- Liest normalisierte Inventory-Ergebnisse.
- Aktionen: `keep`, `downgrade`, `archive`, `delete_candidate`, `promote_candidate`, `summarize_candidate`.
- Schreibt nur Plan, veraendert Store nicht.
- Permanent/User-Memories nie als automatisches Delete markieren.

Part 02 `ApplyApprovedMaintenance`:
- Wendet nur:
  - sichere automatische Archive fuer expired temporary Memories,
  - User-approved Aktionen,
  - explizit konfigurierte Low-Risk-Regeln an.
- Vor Aenderung Backup.
- Audit-Log mit before/after Hash.

Regeln:
- Automatisch erzeugte Memory startet `temporary` oder `run_scoped`.
- Temporary braucht TTL, Default 7 Tage.
- 30 Tage nicht genutzt => Downgrade-/Archive-Kandidat.
- Nie selektiert und aelter als 30 Tage => Archive-Kandidat.
- Duplicate => aeltere Version archivieren, wenn Inhalt/Scope wirklich gleich.
- `run_scoped -> permanent` nur User-Freigabe.
- Delete standardmaessig nur nach Archiv.

Akzeptanzkriterien:
- Analyse und Mutation sind getrennte Checkpoints.
- Kein aggressives Loeschen.
- Jeder Apply-Schritt ist reversibel.
```

### Prompt 9F - Master-Issue-Kontext nur bei echten Aenderungen aktualisieren

```text
Du bist Master-Issue-Memory-Agent. Implementiere SUB-RUN-04.

Part 01 `SyncIssueRelationships`:
- Nutzt bevorzugt explizite Felder/Links aus Issue-/Project-/Task-Journal-Daten.
- Labels oder Namensmuster nur als Fallback mit `confidence`.
- Speichert Relation `{master_issue, sub_issue, source, confidence, updated_at}`.
- Keine LLM-Nutzung.

Part 02 `UpdateChangedMasterIssueSummaries`:
- Aktiv nur, wenn Beziehung, relevante Entscheidung, Constraint oder Status seit letztem Hash geaendert ist.
- Maximal ein LLM-Call pro geaendertem Master-Issue und Lauf.
- Input: nur Delta plus vorhandene kurze Summary, keine kompletten Issue-Historien.
- Output maximal 800 Tokens und Schema:
  `{ goal, constraints, decisions, open_risks, child_issues, updated_at }`
- Bei keiner Aenderung `skipped=unchanged`.

Injektion:
- Nur fuer direkt zugeordnetes Sub-Issue.
- Aktuelle Issue-Beschreibung hat Vorrang.
- Nach Abschluss/Inaktivitaet archivieren.

Akzeptanzkriterien:
- Keine LLM-Kosten ohne geaenderten Kontext.
- Keine kompletten Issue-Bodies in Memories.
- Beziehung und Confidence sind nachvollziehbar.
```

### Prompt 9G - Schlankes Dashboard fuer Optimizer-, Memory- und Run-Statistiken

```text
Du bist Dashboard-Agent. Erweitere das Dashboard nach Punkt 5C, ohne neue Live-Log-Ansicht.

Zu aendernde Dateien:
- `web/Dashboard/src/pages/DashboardPage.tsx`
- `web/Dashboard/src/pages/SettingsPage.tsx`
- `web/Dashboard/src/pages/MemoryPanel.tsx`
- `web/Dashboard/src/types.ts`
- `web/Dashboard/vite.config.ts`
- `var/db/dashboard-state.json`
- `var/db/autopilot-memories.json`
- `var/db/optimizer-change-log.json`

Optimizer-Ansicht:
- Offene Proposals: Rule-ID, Ziel, Evidence, Samples, Risiko, Wirkung, Rollback.
- Aktionen: `approve`, `reject`, `defer`, `create_issue`.
- `approve` bei High-Risk bedeutet nur Issue-Erstellung, nie Auto-Apply.
- Applied Changes zeigen Beobachtungsfenster und Outcome.

Memory-Ansicht:
- Typ, Status, Scope, Ablauf, letzte Nutzung, UseCount, Score.
- Maintenance-Kandidaten mit geplanter Aktion.
- Aktionen: Scope einschraenken, archivieren, permanent setzen.
- Permanent setzen erfordert bestaetigte User-Aktion.

Settings:
- `optimizer.auto_apply_low_risk=false`.
- Observation Window: Runs und Tage.
- Memory MaxItems/MaxTokens.
- Router-Kontrollen aus 4B.

Run-Statistik:
- Verwendet `/run-summary.json`.
- Zeigt Fallbacks, ResumeCount und reused Parts.
- Keine Rohlogs.

API-Sicherheit:
- Aktionen gegen erlaubte Statusuebergaenge validieren.
- Atomare Writes und Backups.
- Keine Dateipfade aus Userinput akzeptieren.

Akzeptanzkriterien:
- User erkennt Grund, Risiko und Evidence jeder Optimierung.
- User kann Memory-Scope und Maintenance kontrollieren.
- Dashboard bleibt kompakt und nutzt keine Live-Log-Komponente.
- `npm run typecheck` und `npm run build` erfolgreich.
```

## Empfohlene Ausfuehrungsreihenfolge

1. Offene Fehler aus 1B/1C beheben.
2. 4A Topologie-Test.
3. 4C State-Schema und Run-History.
4. 4B Router und Dashboard-Konfiguration.
5. 5A Logging-Core.
6. 5B Prozesslogging.
7. 5C Run-Zusammenfassungen statt Live-Log.
8. 8A Provider-Normalisierung.
9. 7A Provider-Test-Suite.
10. 6A Provider-Runner.
11. 6C Checkpoint/Resume.
12. 6B Deliberation-Migration.
13. 7B/7C CLI-Audit und Output-Validierung.
14. 8B Retention.
15. 9A bis 9C Optimizer.
16. 9D bis 9F MemoryOptimization.
17. 9G Dashboard-Kontrollen.

Abschlussregel:

- Ein Prompt gilt erst als abgeschlossen, wenn Code, fokussierte Tests, bestehende Regressionstests und der jeweilige Datenvertrag gemeinsam bestanden sind.
- Reine Auditberichte oder ein erfolgreicher Vite-Build ohne Typecheck reichen nicht als Abschlussnachweis.
