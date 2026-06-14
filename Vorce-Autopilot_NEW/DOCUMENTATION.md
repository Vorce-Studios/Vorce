# Vorce-Autopilot NEW — System-Dokumentation

> **Version:** 3.0-NEW | **Stand:** 2026-06-14

---

## 1. Architektur-Übersicht

Vorce-Autopilot NEW ist ein modulares, datengetriebenes Framework zur autonomen Orchestrierung von KI-Agenten (Gemini CLI, Claude Code, Jules) für das Vorce-Studios/Vorce Repository.

### Hierarchiemodell

```
autopilot.ps1           ← Wächter-Loop mit Rolling-Log und Wakeup-Signal
    │
    └─► Vorce-Orchestrator.ps1   ← Wählt den aktiven Main-Run per Scheduling
            │
            ├─► MAIN-RUN-01_Planning/Planning-Router.ps1
            │       ├─► SUB-RUN-01_DataSync   → PART-RUN-01_FetchIssues
            │       │                          → PART-RUN-02_FetchPRs
            │       ├─► SUB-RUN-02_Triage      → PART-RUN-03_FilterIssues
            │       ├─► SUB-RUN-03_Strategy    → PART-RUN-04_CreateProposal (Deliberation)
            │       └─► SUB-RUN-04_Delegation  → Jules-Task-Erstellung
            │
            ├─► MAIN-RUN-02_CheckAndDoing/CheckAndDoing-Router.ps1
            │       ├─► SUB-RUN-01_SessionSync
            │       ├─► SUB-RUN-02_JulesCheck
            │       ├─► SUB-RUN-03_LocalAgentCheck
            │       └─► SUB-RUN-04_ReviewDispatch
            │
            └─► MAIN-RUN-03_Audit/Audit-Router.ps1
                    └─► SUB-RUN-01_ComplianceCheck
```

### Ausführungsebenen

| Ebene | Datei-Pattern | Zweck | Parallelität |
|-------|---------------|-------|-------------|
| **Main-Run** | `MAIN-RUN-[NN]_[Name]/` | Übergeordneter Aufgabenbereich | Sequenziell |
| **Router** | `[Name]-Router.ps1` | Entscheidet dynamisch welche Sub-Runs nötig sind | Einmalig |
| **Sub-Run** | `SUB-RUN-[NN]_[Name].ps1` | Logisches Aufgabenpaket | Sequenziell |
| **Part-Run** | `PART-RUN-[NN]_[Name].ps1` | Atomare Operation (1 API-Aufruf oder Agent-Call) | Parallel (via RunEngine) |

---

## 2. Datei & Code Bezeichnungen

### PowerShell-Module (`src/lib/`)

| Datei | Zweck | Schlüsselfunktionen |
|-------|-------|---------------------|
| `StatusPrinter.ps1` | Terminal-Ausgaben | `Write-VorceHeader`, `Write-VorceStep`, `Write-VorceFooter`, `Write-VorceDivider` |
| `StateManager.ps1` | JSON-State Verwaltung | `Read-VorceGlobalState`, `Save-VorceGlobalState`, `Initialize-RunState` |
| `ApiClient.ps1` | Basis REST-Client | `Invoke-VorceApiRequest` |
| `GitHubClient.ps1` | GitHub-Datenabruf (gh CLI) | `Get-VorceGitHubIssues`, `Get-VorceGitHubPRs`, `Save-VorceGitHubData` |
| `ProjectManager.ps1` | GitHub Project V2 Board | `Sync-VorceProjectState`, `Get-VorceProjectSettings` |
| `AgentRunner.ps1` | KI-Agent Ausführung | `Invoke-VorceAgent` (unterstützt: `gemini_cli`, `claude_code`) |
| `PromptManager.ps1` | Prompt-Laden & Templating | `Get-VorcePrompt` (unterstützt `{{Variable}}` Syntax) |
| `RunEngine.ps1` | Parallele PART-RUN Ausführung | `Invoke-VorcePartRun`, `Invoke-VorceSubRunParallel` |
| `QuotaManager.ps1` | API-Quoten-Verwaltung | `Test-VorceQuota`, `Register-VorceQuotaUsage`, `Get-VorceRemainingQuota` |
| `DeliberationEngine.ps1` | Dual-Agent Deliberation | `Invoke-VorceDeliberation` (Proposal → Critique → Synthesis) |
| `TriageUtils.ps1` | Issue-Filterung | `Get-VorceTriagedIssues` |

### Naming-Konventionen

```
PowerShell-Funktionen:  [Verb]-Vorce[Kontext]
  Beispiel:  Invoke-VorceAgent, Save-VorceGlobalState, Test-VorceQuota

Run-Skripte:  [TYP]-RUN-[NN]_[Beschreibung].ps1
  Beispiel:  MAIN-RUN-01_Planning, SUB-RUN-02_Triage, PART-RUN-03_FilterIssues

Run-State JSONs:  [TYP]_[Beschreibung].json  (in var/run-states/)
  Beispiel:  MAIN_Planning.json, SUB_DataSync.json, PART_FetchIssues.json

Datenbank-Dateien:  [kontext]-[typ].json  (in var/db/)
  Beispiel:  github-issues.json, global-state.json, triaged-issues.json

Prompt-Dateien:  [aufgabe].md  (in var/prompts/[kategorie]/)
  Beispiel:  planning_session.md, jules_implementation.md
```

---

## 3. Globale Variablen (Pflicht-Pattern)

`autopilot.ps1` setzt beim Start verbindlich:

```powershell
$global:VorceRoot = $PSScriptRoot          # Absoluter Wurzelpfad
$global:VarDir    = Join-Path $global:VorceRoot "var"
$global:SrcDir    = Join-Path $global:VorceRoot "src"
$global:LibDir    = Join-Path $global:SrcDir    "lib"
```

**Alle Module** lösen Pfade zu `var/` über `$global:VarDir` auf — **niemals** über `$PSScriptRoot` des Moduls selbst. Das verhindert Pfad-Fehler in Background-Jobs und bei verschachtelten Dot-Sources.

---

## 4. Daten- & Kommunikationsfluss

### Datenfluss (Read/Write)

```
var/config/autopilot-config.json  ──read──►  Orchestrator, Router, AgentRunner
var/config/quota-registry.json    ──read──►  QuotaManager

GitHub API  ──► GitHubClient  ──write──►  var/db/github-issues.json
                                           var/db/pull-requests.json

TriageUtils  ──read──  var/db/github-issues.json
             ──write── var/db/triaged-issues.json

DeliberationEngine  ──read──  var/db/triaged-issues.json
                    ──write── var/db/proposals/proposal_[N].md

Orchestrator/RunEngine  ──write──  var/run-states/[TYP]_[Name].json
                        ──write──  var/db/global-state.json  (Dashboard-Trigger)

autopilot.ps1  ──write──  var/log/autopilot_[timestamp].log
AgentRunner    ──write──  var/tmp/  (output_*.txt, error_*.txt — werden nach Aufruf gelöscht)
```

### Run-State Schema

Jeder Run-State in `var/run-states/` folgt diesem JSON-Schema:
```json
{
  "id":           "run_20260614_143000",
  "name":         "MAIN-RUN-01_Planning",
  "type":         "MAIN",
  "status":       "completed",   // initialized | in_progress | completed | failed
  "started_at":   "2026-06-14T14:30:00.000Z",
  "completed_at": "2026-06-14T14:45:00.000Z",
  "metadata":     {},
  "results":      []
}
```

---

## 5. Scheduling & Laufzeitsteuerung

### Wake-Intervalle (aus `autopilot-config.json`)

| Main-Run | Intervall | Zweck |
|----------|-----------|-------|
| `MAIN-RUN-01_Planning` | alle 120 min | Issues triagieren, Proposals erstellen, Jules delegieren |
| `MAIN-RUN-02_CheckAndDoing` | alle 15 min | Jules-Sessions monitoren, PRs reviewen |
| `MAIN-RUN-03_Audit` | alle 60 min | Compliance, Gesundheits-Check |

### Wakeup-Signal

Neben dem Timer-basierten Loop kann `autopilot.ps1` sofort durch eine Wakeup-Datei geweckt werden:
```powershell
# Von außen auslösen:
New-Item (Join-Path $AutopilotRoot "autopilot.wakeup") -Force
```

### Scheduling-Logik im Orchestrator

```powershell
function Select-NextMainRun {
    param($GlobalState, $Config)
    # Vergleicht $GlobalState.last_runs.[RunName] mit aktuellem Timestamp
    # und wake_intervals aus Config
    # Gibt den Main-Run zurück dessen Intervall am längsten überschritten ist
}
```

---

## 6. Agent-Aufruf & Quoten

### Unterstützte Agenten

| Agent-ID | CLI-Befehl | Typ |
|----------|-----------|-----|
| `gemini_cli` | `gemini.ps1 --yolo` | Prompt via stdin |
| `claude_code` | `claude.cmd --prompt` | Prompt als Argument |

### Quota-Prüfung (Pflicht vor jedem Agent-Call)

```powershell
# In AgentRunner.ps1 MUSS vor Start-Process stehen:
if (-not (Test-VorceQuota -AgentName $AgentName -ModelTier $ModelTier)) {
    Write-VorceStep "Quota erschöpft für $AgentName/$ModelTier" -Status "WARN"
    return $null
}
Register-VorceQuotaUsage -AgentName $AgentName -ModelTier $ModelTier
```

---

## 7. Deliberation-System

Das Dual-Agent Deliberationsmodell ermöglicht hochwertige Entscheidungen durch drei Phasen:

| Phase | Prompt-Datei | Beschreibung |
|-------|-------------|-------------|
| **1. Proposal** | `var/prompts/deliberation/proposal.md` | Agent A erstellt einen Vorschlag |
| **2. Critique** | `var/prompts/deliberation/critique.md` | Agent B (oder A) prüft und kritisiert |
| **3. Synthesis** | `var/prompts/deliberation/synthesis.md` | Agent A synthetisiert das finale Ergebnis |

Template-Variablen im Prompt: `{{IssueNumber}}`, `{{IssueTitle}}`, `{{IssueBody}}`, `{{CeoProposal}}`, `{{QaCritique}}`

---

## 8. Terminal-Ausgabe Standard

Alle Ausgaben laufen über `StatusPrinter.ps1`:

```
============================================================
  🧠 ORCHESTRATOR ACTIVE
============================================================
[14:30:01] [ ⏩ ] Starte MAIN-RUN-01_Planning (1/3)
[14:30:02] [ ℹ️  ] Analysiere Bedarf via Router...
[14:30:03] [ ⏩ ] Starte Sub-Run: SUB-RUN-01_DataSync
------------------------------------------------------------
[14:30:05] [ ✅ ] 42 Issues erfolgreich geladen.
[14:30:06] [ ✅ ] Sub-Run DataSync abgeschlossen.
============================================================
  DONE: MAIN-RUN-01_Planning erfolgreich beendet.
============================================================
```

**Status-Icons:**
- `[ ⏩ ]` — RUN (laufend)
- `[ ✅ ]` — OK (erfolgreich)
- `[ ⚠️  ]` — WARN (Warnung, nicht fatal)
- `[ ❌ ]` — ERROR (Fehler, wird geloggt)
- `[ ℹ️  ]` — INFO (neutral)

---

## 9. Fehlerbehandlung

| Ebene | Strategie |
|-------|-----------|
| **Part-Run** | Try/Catch → Status `"failed"` im State, `RunEngine` läuft weiter |
| **Sub-Run** | Try/Catch → Fehler geloggt, Orchestrator läuft mit nächstem Sub-Run weiter |
| **Main-Run** | Try/Catch → Fehler geloggt, `autopilot.ps1` Loop wartet Intervall ab, dann neuer Versuch |
| **Agent-Aufruf** | Exit-Code ≠ 0 → `null` zurückgeben, aufrufendes Modul entscheidet über Fallback |
| **Quota** | Quota erschöpft → `null` zurückgeben + WARN, kein Crash |
