# Vorce-Autopilot NEW — Refactoring-Plan (Überarbeitete Fassung)

> **Letzte Aktualisierung:** 2026-06-14  
> **Ziel:** Vollständig funktionsfähiges, modulares Autopilot-Framework ohne Legacy-Abhängigkeiten.  
> **Naming-Konvention:** Alle PowerShell-Funktionen beginnen mit dem Präfix `Invoke-Vorce*`, `Get-Vorce*`, `Save-Vorce*`, `Write-Vorce*` oder `Sync-Vorce*`. Dateinamen beschreiben exakt ihre Rolle: `[Verb]-[Kontext].ps1` (z.B. `Invoke-PlanningRun.ps1`). Run-Skripte folgen `[TYP]-RUN-[NN]_[Name].ps1`.

---

## 1. Architektonisches Leitbild

**Paradigma:** Datengetriebes Multi-Ebenen-Framework. Kein Skript kennt die Implementierungsdetails einer anderen Ebene — Kommunikation läuft ausschließlich über standardisierte Run-State JSONs.

**Schichten:**
```
autopilot.ps1 (Loop/Wächter)
    └─► Vorce-Orchestrator.ps1 (Hierarchie-Steuerung)
            └─► [MAIN-RUN]-Router.ps1 (Auswahl der Sub-Runs)
                    └─► [SUB-RUN].ps1 (Aufgabenpaket)
                            └─► RunEngine → [PART-RUN].ps1 (atomarer Agent-Aufruf)
```

**Zero-Legacy-Regel:** Kein Code aus V1/V2 darf direkt kopiert werden. Nur getestete Logik darf als Referenz dienen.

---

## 2. Finale Verzeichnisstruktur (kanonisch)

```text
Vorce-Autopilot_NEW/
├── autopilot.ps1                        # Wächter-Loop (Init → Orchestrator)
├── Start-Autopilot.ps1                  # Infrastruktur-Bootstrapper (Dashboard, Sync)
│
├── src/
│   ├── lib/                             # Alle wiederverwendbaren Module
│   │   ├── StatusPrinter.ps1            # Terminal-Ausgaben (Icons, Farben, Timestamps)
│   │   ├── StateManager.ps1             # Lesen/Schreiben von Run-States & Global-State
│   │   ├── ApiClient.ps1                # Basis REST-Client (Auth-Header-Management)
│   │   ├── GitHubClient.ps1             # GitHub-spez. Abfragen (Issues, PRs) via gh CLI
│   │   ├── ProjectManager.ps1           # GitHub Project V2 Board Sync
│   │   ├── AgentRunner.ps1              # KI-Agent CLI Ausführung (gemini, claude, etc.)
│   │   ├── PromptManager.ps1            # Laden & Template-Ersetzung von .md Prompts
│   │   ├── RunEngine.ps1                # Parallele PART-RUN Ausführung & Aggregation
│   │   ├── QuotaManager.ps1             # [FEHLT] Quoten-Prüfung vor Agent-Aufrufen
│   │   ├── DeliberationEngine.ps1       # Dual-Agent Deliberation (Proposal→Critique→Synthesis)
│   │   └── TriageUtils.ps1              # Issue-Filterung nach Label-Regeln
│   │
│   ├── orchestrator/
│   │   └── Vorce-Orchestrator.ps1       # Haupt-Dispatcher (lädt Runs, ruft Router, aggregiert)
│   │
│   └── runs/
│       ├── MAIN-RUN-01_Planning/
│       │   ├── Planning-Router.ps1      # [STUB] → muss dynamisch werden
│       │   ├── SUB-RUNS/
│       │   │   ├── SUB-RUN-01_DataSync.ps1      # Issues + PRs holen
│       │   │   ├── SUB-RUN-02_Triage.ps1        # [STUB] Triage-Logik
│       │   │   ├── SUB-RUN-03_Strategy.ps1      # [STUB] Strategie via Deliberation
│       │   │   └── SUB-RUN-04_Delegation.ps1    # [FEHLT] Jules-Aufgaben verteilen
│       │   └── PART-RUNS/
│       │       ├── PART-RUN-01_FetchIssues.ps1
│       │       ├── PART-RUN-02_FetchPRs.ps1
│       │       ├── PART-RUN-03_FilterIssues.ps1
│       │       └── PART-RUN-04_CreateProposal.ps1
│       │
│       ├── MAIN-RUN-02_CheckAndDoing/   # [FEHLT] Vollständig
│       │   ├── CheckAndDoing-Router.ps1
│       │   └── SUB-RUNS/
│       │       ├── SUB-RUN-01_SessionSync.ps1
│       │       ├── SUB-RUN-02_JulesCheck.ps1
│       │       ├── SUB-RUN-03_LocalAgentCheck.ps1
│       │       └── SUB-RUN-04_ReviewDispatch.ps1
│       │
│       └── MAIN-RUN-03_Audit/           # [FEHLT] Vollständig
│           ├── Audit-Router.ps1
│           └── SUB-RUNS/
│               └── SUB-RUN-01_ComplianceCheck.ps1
│
├── test/
│   ├── Test-Boot.ps1                    # [FEHLT] Checkpoint 1 Test
│   ├── Test-OrchestratorDryRun.ps1      # [FEHLT] Checkpoint 2 Test
│   └── Test-StartProcess.ps1            # Vorhanden
│
├── web/Dashboard/                       # Vite/React Dashboard
│
└── var/                                 # EINZIGER Schreibort für Laufzeitdaten
    ├── config/
    │   ├── autopilot-config.json        # Betriebsparameter
    │   └── quota-registry.json          # API-Quotenregeln
    ├── db/
    │   ├── global-state.json            # Systemzustand (Dashboard-Quelle)
    │   ├── github-issues.json           # Gecachte Issues
    │   ├── pull-requests.json           # Gecachte PRs
    │   ├── triaged-issues.json          # Gefilterte Issues
    │   ├── task-journal.json            # Aufgaben-Protokoll
    │   └── proposals/                   # [FEHLT Ordner-Deklaration] Planungs-Proposals
    ├── log/                             # [FEHLT im Dateisystem] Rolling Logs (max 10)
    ├── prompts/
    │   ├── system/                      # CEO-System-Prompt, Dashboard-Anweisungen
    │   ├── jules/                       # Jules Implementierungs- & Review-Prompts
    │   ├── phases/                      # Phasen-Prompts (planning, triage, etc.)
    │   └── deliberation/                # Deliberation-Prompts (proposal, critique, synthesis)
    ├── run-states/                      # JSON-Handoffs zwischen Runs
    └── tmp/                             # Temporäre Dateien (Agent I/O)
```

---

## 3. Identifizierte Defizite & Korrekturbedarf

### 3.1 Kritische Fehler (Blocker)

| # | Datei | Problem | Lösung |
|---|-------|---------|--------|
| C1 | `StateManager.ps1` | `$PSScriptRoot` zeigt auf `src/lib/` — relative Pfade zu `var/` sind **falsch** wenn das Modul per Dot-Sourcing aus anderen Skripten geladen wird (z.B. aus `SUB-RUNS/`). Der Pfad `../../var/db/` stimmt nur wenn der Aufrufer in `src/orchestrator/` sitzt. | `$VarDir` muss als **Parameter** übergeben oder über eine Root-Variable (`$global:VorceRoot`) aufgelöst werden. |
| C2 | `RunEngine.ps1` → `Invoke-VorceSubRunParallel` | Im Background-Job wird `Invoke-VorcePartRun` aufgerufen, das selbst `Initialize-RunState` nutzt — aber der Job hat **keinen Zugriff** auf `$VarDir` (nicht serialisierbar). Der Pfad `../../var/run-states/` bricht im Job-Kontext. | `$VarDir` als Job-Argument mitgeben; alle Pfad-Auflösungen müssen absolut und explizit übergeben werden. |
| C3 | `ApiClient.ps1` | Hat `Export-ModuleMember` obwohl die Datei per Dot-Sourcing (`.`) geladen wird — `Export-ModuleMember` ist **nur** in echten `.psm1`-Modulen gültig und wirft einen Fehler beim Dot-Sourcing. | `Export-ModuleMember` entfernen oder alle Libs auf `.psm1` umstellen (dann `Import-Module` nutzen). |
| C4 | `Vorce-Orchestrator.ps1` | Der Orchestrator ist **hart auf `MAIN-RUN-01_Planning` fest verdrahtet** (Zeile 20). Es gibt keine Logik um zu entscheiden, welcher Main-Run als nächstes dran ist (Planning vs. CheckAndDoing vs. Audit). | Scheduling-Logik via `autopilot-config.json` `wake_intervals` einbauen; der Orchestrator muss den richtigen Main-Run anhand eines Timestamps auswählen. |
| C5 | `SUB-RUN-01_DataSync.ps1` | Lädt `RunEngine.ps1` aber **nicht** `StateManager.ps1` und `GitHubClient.ps1`, die intern genutzte Funktionen definieren (`Initialize-RunState`, `Get-VorceGitHubIssues`). | Alle benötigten Module explizit laden. |
| C6 | `PART-RUN-04_CreateProposal.ps1` | Repository-Name `"Vorce-Studios/Vorce"` und Dashboard-Pfade sind **hardkodiert** (Zeile 29-32). Bei Konfigurationsänderung bricht der Code. | Werte aus `autopilot-config.json` lesen. |

### 3.2 Fehlende Implementierungen (Lücken)

| # | Was fehlt | Priorität |
|---|-----------|-----------|
| L1 | `QuotaManager.ps1` — Modul existiert nicht, obwohl REBUILD_STATUS es als 🟢 markiert (falsch!) | **HOCH** |
| L2 | `var/log/` Verzeichnis existiert nicht auf Dateisystem | MITTEL |
| L3 | `var/db/proposals/` Verzeichnis existiert nicht | MITTEL |
| L4 | `SUB-RUN-04_Delegation.ps1` fehlt (in Config referenziert, aber nicht implementiert) | HOCH |
| L5 | `MAIN-RUN-02_CheckAndDoing/` komplett fehlend (alle Router + 4 Sub-Runs) | HOCH |
| L6 | `MAIN-RUN-03_Audit/` komplett fehlend | NIEDRIG |
| L7 | `Test-Boot.ps1` und `Test-OrchestratorDryRun.ps1` fehlen (Checkpoints ungetestet!) | HOCH |
| L8 | Dashboard: `vite.config.ts` muss File-Watcher auf `var/db/*.json` implementieren | MITTEL |
| L9 | Orchestrator hat keine Fehlerbehandlung für fehlgeschlagene Sub-Runs (Loop bricht ab) | HOCH |
| L10 | `Planning-Router.ps1` ist reiner Stub — enthält null Entscheidungslogik | MITTEL |

### 3.3 Dokumentations-Inkonsistenzen

| # | Dokument | Problem |
|---|----------|---------|
| D1 | `REBUILD_STATUS.md` | `QuotaGuard.ps1` ist in REFACTORING_PLAN erwähnt (Abschnitt 2), aber das tatsächlich existierende Modul heißt in REBUILD_STATUS `QuotaManager.ps1` — und beide existieren **nicht** als Datei. |
| D2 | `REBUILD_STATUS.md` | `RunEngine.ps1` als 🟢 markiert obwohl kritische Pfad-Bugs vorhanden (C2). |
| D3 | `REFACTORING_PLAN.md` | Verzeichnisstruktur zeigt `tools/` in `src/` — existiert nicht und ist nicht implementiert. |
| D4 | `DOCUMENTATION.md` | Beschreibt Dashboard-Sync über `vite.config.ts` — das ist technisch falsch (Vite Config steuert keinen File-Watcher für Runtime-Daten). Korrekt wäre ein WebSocket-Server oder ein Polling-Backend in der React-App selbst. |
| D5 | `autopilot-config.json` | Referenziert `kiro_cli` als Agent — dieser ist nicht in `AgentRunner.ps1` implementiert. |
| D6 | `PART-RUN-04_CreateProposal.ps1` | Liest `triaged[0]` ohne zu prüfen ob das Array leer ist (nach dem `Count == 0` Check bleibt der Code anfällig wenn `$triaged` kein Array ist). |

---

## 4. Implementierungs-Phasen (Korrigiert & Detailliert)

### Phase 1 — Fundament fixieren ✅ Teilweise erledigt, Bugs beheben

**Ziel:** Boot läuft fehlerfrei, alle Pfad-Probleme behoben, Logging aktiv.

- [x] Ordnerstruktur `src/`, `var/` angelegt
- [ ] **C1 beheben:** `StateManager.ps1` — `$VarDir` via `$global:VorceRoot` auflösen
  ```powershell
  # In autopilot.ps1 EINMALIG setzen:
  $global:VorceRoot = $PSScriptRoot
  # In StateManager.ps1 nutzen:
  $varDir = Join-Path $global:VorceRoot "var"
  ```
- [ ] **C3 beheben:** `Export-ModuleMember` aus `ApiClient.ps1` entfernen
- [ ] **L2 beheben:** `var/log/` Ordner via `Start-Autopilot.ps1` sicherstellen
- [ ] **L3 beheben:** `var/db/proposals/` sicherstellen
- [ ] **Test-Boot.ps1** schreiben: Prüft ob alle Dirs existieren, alle Module dot-sourcebar sind, Log-Datei erstellt wird
- **Checkpoint 1:** `Test-Boot.ps1` läuft grün durch

### Phase 2 — Orchestrator-Kern stabilisieren

**Ziel:** Orchestrator kann dynamisch den richtigen Main-Run wählen und Fehler überleben.

- [ ] **C4 beheben:** `Vorce-Orchestrator.ps1` — Main-Run Scheduling einbauen
  ```powershell
  # Logik: Vergleiche last_run Timestamps aus global-state.json
  # mit wake_intervals aus autopilot-config.json
  function Select-NextMainRun { ... }
  ```
- [ ] **L9 beheben:** Try/Catch um jeden Sub-Run-Aufruf im Orchestrator; failed Sub-Runs loggen und weiterlaufen
- [ ] **QuotaManager.ps1** implementieren (war als `QuotaGuard.ps1` geplant, heißt jetzt einheitlich `QuotaManager.ps1`):
  - Funktionen: `Test-VorceQuota`, `Register-VorceQuotaUsage`, `Get-VorceRemainingQuota`
  - Liest aus `var/config/quota-registry.json`
  - Wird in `AgentRunner.ps1` VOR jedem Agent-Aufruf gecallt
- [ ] **Test-OrchestratorDryRun.ps1** schreiben
- **Checkpoint 2:** Orchestrator wählt korrekten Main-Run, übersteht Sub-Run-Fehler, schreibt korrekten JSON-State

### Phase 3 — MAIN-RUN-01_Planning vollständig machen

**Ziel:** Ein kompletter Planning-Lauf (DataSync → Triage → Strategy → Delegation) läuft durch.

- [ ] **C2 beheben:** `RunEngine.ps1` — `$VarDir` als Parameter in Jobs übergeben
- [ ] **C5 beheben:** `SUB-RUN-01_DataSync.ps1` alle Abhängigkeiten laden
- [ ] **C6 beheben:** `PART-RUN-04_CreateProposal.ps1` — Config aus JSON lesen statt hardcoden
- [ ] **L10 beheben:** `Planning-Router.ps1` — echte Entscheidungslogik einbauen:
  - Quota prüfen (via QuotaManager)
  - Zeitstempel des letzten Runs prüfen
  - Anzahl neuer Issues prüfen
- [ ] **L4:** `SUB-RUN-04_Delegation.ps1` implementieren:
  - Liest `var/db/proposals/` 
  - Erstellt Jules-Tasks (via `gh issue create` oder Jules-API)
  - Speichert Ergebnis in `var/db/task-journal.json`
- [ ] **SUB-RUN-02_Triage.ps1** vollständig implementieren (aktuell Stub):
  - Lädt Issues aus `var/db/github-issues.json`
  - Ruft `Get-VorceTriagedIssues` auf
  - Speichert in `var/db/triaged-issues.json`
- [ ] **SUB-RUN-03_Strategy.ps1** vollständig implementieren (aktuell Stub):
  - Ruft `Invoke-VorceDeliberation` für jedes triagierte Issue auf
  - Speichert Proposals in `var/db/proposals/`
- **Checkpoint 3:** Dry-Run mit echten GitHub-Daten — vollständige JSON-Spur in `var/run-states/` + Proposals in `var/db/proposals/`

### Phase 4 — MAIN-RUN-02_CheckAndDoing implementieren

**Ziel:** Kontinuierliches Monitoring von Jules-Sessions und PR-Status.

- [ ] `CheckAndDoing-Router.ps1` — Stub + Grundlogik
- [ ] `SUB-RUN-01_SessionSync.ps1` — PR-Status aller offenen Jules-PRs prüfen
- [ ] `SUB-RUN-02_JulesCheck.ps1` — Jules-Sessions auslesen (via gh API oder `var/db/`)
- [ ] `SUB-RUN-03_LocalAgentCheck.ps1` — Laufende lokale Agent-Prozesse prüfen
- [ ] `SUB-RUN-04_ReviewDispatch.ps1` — Fertige PRs zur Review dispatchen (via Gemini/Claude)
- **Checkpoint 4:** CheckAndDoing-Lauf prüft PRs und updated `var/db/global-state.json`

### Phase 5 — Dashboard & Polishing

**Ziel:** Dashboard zeigt Echtzeit-Daten; System ist produktionsreif.

- [ ] **D4 beheben:** Dashboard-Sync korrekt implementieren (Polling `var/db/*.json` alle 5s, NICHT via vite.config)
- [ ] Log-Rotation in `autopilot.ps1` (max. 10 Dateien in `var/log/`)  
- [ ] `MAIN-RUN-03_Audit/` minimale Implementierung
- [ ] Alle DEBUG `Write-VorceStep` Zeilen aus `AgentRunner.ps1` entfernen/optional machen
- [ ] End-to-End Test: Echter Planning-Lauf mit GitHub API

---

## 5. Naming-Konventionen (verbindlich)

| Typ | Konvention | Beispiel |
|-----|-----------|---------|
| PowerShell-Modul | `[Kontext].ps1` (PascalCase) | `StateManager.ps1` |
| PowerShell-Funktion | `[Verb]-Vorce[Kontext]` | `Invoke-VorceAgent` |
| Main-Run | `MAIN-RUN-[NN]_[Name].ps1` | `MAIN-RUN-01_Planning.ps1` |
| Sub-Run | `SUB-RUN-[NN]_[Name].ps1` | `SUB-RUN-02_Triage.ps1` |
| Part-Run | `PART-RUN-[NN]_[Name].ps1` | `PART-RUN-03_FilterIssues.ps1` |
| Router | `[RunName]-Router.ps1` | `Planning-Router.ps1` |
| Run-State JSON | `[TYP]_[Name].json` | `SUB_DataSync.json`, `MAIN_Planning.json` |
| DB-Datei | `[kontext]-[typ].json` (kebab-case) | `github-issues.json`, `global-state.json` |
| Prompt-Datei | `[aufgabe].md` (kebab-case) | `planning_session.md`, `jules_implementation.md` |

---

## 6. Globale Variable (Pflicht)

`autopilot.ps1` **muss** als allererstes setzen:
```powershell
$global:VorceRoot = $PSScriptRoot   # Absoluter Pfad zu Vorce-Autopilot_NEW/
$global:VarDir    = Join-Path $global:VorceRoot "var"
$global:SrcDir    = Join-Path $global:VorceRoot "src"
$global:LibDir    = Join-Path $global:SrcDir "lib"
```
Alle Module lösen Pfade relativ zu `$global:VorceRoot` auf — **niemals** relativ zu `$PSScriptRoot` des Moduls selbst (außer für eigene interne Assets).
