# Vorce-Autopilot 2.0 - Workflow-Analyse & Fehlerbericht

**Erstellt:** 2026-06-11  
**Analyst:** Hermes Agent  
**Fokus:** MAIN-RUN Workflows inkl. SUB-RUNs und PART-RUNs

---

## Executive Summary

Die Vorce-Autopilot 2.0 Architektur zeigt eine solide hierarchische Struktur mit klaren Trennungen zwischen MAIN-RUN ( Planning / Check&Doing / Audit / Optimizer), SUB-RUNs (dynamischen Tasks) und PART-RUNs (Agenten-Delegate). Die Workflow-Logik ist generell durchdacht, aber es wurden **5 kritische Fehler**, **4 mittelschwere Probleme** und **6 Optimierungsvorschläge** identifiziert.

---

## 1. CRITICAL ERRORS (5)

### 1.1 [CRITICAL] ROUTER-Script `ROUTER_MAIN-RUN-02_CheckAndDoing.ps1` Referenziert `$QuotaRegistry`ohne Parameter

**Datei:** `src/runs/ROUTER/ROUTER_MAIN-RUN-02_CheckAndDoing.ps1`  
**Linien:** 69-95 (JulesRefill-Block)

```powershell
# ZEILE 73:
$julesProvider = $QuotaRegistry.providers.jules
```

**Problem:** Die `$QuotaRegistry` Variable wird im ROUTER-Skript **nicht** als Parameter definiert, aber im JulesRefill-Block direkt verwendet. Das führt zu Laufzeitfehler "The variable '$QuotaRegistry' cannot be retrieved".

**Betroffene SUB-RUN:** `SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill.ps1` (wird nie ausgeführt)

**Fix:**

- Entweder `$QuotaRegistry` als Parameter hinzufügen:

  ```powershell
  param(
      [object]$GlobalState,
      [object]$Config,
      [object]$MainState,
      [object]$QuotaRegistry  # <- Hinzufügen
  )
  ```

- Oder `$QuotaRegistry` im Hauptskript (`autopilot.ps1`) laden und übengeben (wie bei MAIN-RUNs).

---

### 1.2 [CRITICAL] `SUB-RUN-02_MR-01_Planning__Triage.ps1` schneidet Issue-Prompt ab

**Datei:** `src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__Triage.ps1`  
**Linien:** 19-25 (promptText)

**Problem:** Der hierationale Deliberations-Prompt für Re-Planning wird **nach 25 Zeilen abgeschnitten**, obwohl der hieratische Block (CEO + QA-Manager + CEO Synthesis) weit über 177 Zeilen lang ist. Der Teil nach Zeile 150 wird **nicht** im Prompt enthalten sein, wodurch QA-Manager und CEO-Synthese **nie** ausgeführt werden.

**Evidenz:**

```powershell
# LINIE 25 ENDE:
$promptText = @"
... (25 Zeilen)
Antworte mit einem konkreten, korrigierten Handlungsplan für Jules.
"@
```

Der Prompt endet nach `Antworte mit...` und enthält **keine** der nachfolgenden Schritte (Critique, Synthesis, GitHub-Comment posten).

**Fix:** Den gesamten hieratischen Block in den Prompt einbinden oder die Prompt-Erstellung in mehrere PART-RUNs aufteilen, wobei jedes PART-RUN seinen eigenen Fokus hat.

---

### 1.3 [CRITICAL] `SUB-RUN-01_MR-02_CheckAndDoing__SessionSync.ps1` Liest State-Datei falsch

**Datei:** `src/runs/SUB-RUN/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync.ps1`  
**Problem:** Die Funktion `Read-AutopilotState` wird aufgerufen, aber das globale `$global:VorceAutopilotStateFilePath` wird nicht korrekt gesetzt, wenn die Variable nicht existiert.

**Evidenz aus `state-manager.ps1`:**

```powershell
if ($null -eq (Get-Variable -Name "VorceAutopilotStateFilePath" -Scope Global -ErrorAction SilentlyContinue)) {
    $global:VorceAutopilotStateFilePath = Join-Path $PSScriptRoot "../../var/db/active-sessions.json"
}
```

Wenn `$PSScriptRoot` im SUB-RUN-Kontext ist, zeigt der Pfad auf `.../SUB-RUN/` statt `.../` und die Datei wird **nicht** gefunden.

**Fix:** Im `session-sync.ps1`-Skript vor dem Aufruf sicherstellen:

```powershell
$global:VorceAutopilotStateFilePath = Join-Path $ScriptDir "var/db/active-sessions.json"
$state = Read-AutopilotState
```

---

### 1.4 [CRITICAL] `autopilot.ps1` - `Test-LocalPortListening` nutzt PowerShell-Only Cmdlet

**Datei:** `Start-Autopilot.ps1`  
**Linien:** 320-328

```powershell
function Test-LocalPortListening {
    param([Parameter(Mandatory)][int]$Port)
    try {
        return $null -ne (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
    } catch {
        return $false
    }
}
```

**Problem:** `Get-NetTCPConnection` ist nur auf Windows 8/2012+ verfügbar. Auf älteren Windows-Versionen oder Windows Server Core fehlt das Modul `NetTCPIP`, was zu einem **Fehler** führt.

**Hinweis:** Da der User auf **Windows 10** arbeitet, ist dies aktuell kein Problem, aber eine **Zukunfts-Blocking-Issue** bei Migration.

**Fix:**

```powershell
function Test-LocalPortListening {
    param([Parameter(Mandatory)][int]$Port)
    try {
        # Fallback für ältere Systeme: Test-Connection auf Port (PowerShell Core)
        return $null -ne (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
    } catch {
        # Fallback: Test-NetConnection (PowerShell 3+)
        try {
            return (Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -ErrorAction SilentlyContinue).TcpTestSucceeded
        } catch {
            return $false
        }
    }
}
```

---

### 1.5 [CRITICAL] `SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1` - Fehlende `_` in Dateinamen-Konvention

**Datei:** `src/runs/SUB-RUN/SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1`  
**Problem:** Der Router `ROUTER_MAIN-RUN-04_Optimizer.ps1` definiert `SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1`, aber die Dateinamenkonvention im Verzeichnis zeigt:

```
SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1   <- Doppelter Unterstrich (__)
```

Der Router-Code in `Invoke-MainRun.ps1` (ZEILE 70) erwartet:

```powershell
$fullSubScriptPath = Join-Path $Script:OrchestratorRoot $subScript
```

Der `$subScript`-Pfad aus dem Router kommt von:

```powershell
script = "src/runs/SUB-RUN/SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1"
```

Das ist **korrekt**, aber die `$Script:OrchestratorRoot` ist `../../`, was zu:

```
../../src/runs/SUB-RUN/SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1
```

führt, was **falsch** ist, da `src/orchestrator/Invoke-MainRun.ps1` den Pfad relativ von `src/orchestrator/` aus interpretiert.

**Fix:** In `Invoke-MainRun.ps1` ZEILE 15:

```powershell
$Script:OrchestratorRoot = $PSScriptRoot  # <- statt "../"
```

ODER in den Router-Pfaden `../src/runs/...` statt `src/runs/...` verwenden.

---

## 2. MEDIUM ISSUES (4)

### 2.1 [MEDIUM] `ROUTER_MAIN-RUN-03_Audit.ps1` - `Test-ObjectProperty` nicht definiert

**Datei:** `src/runs/ROUTER/ROUTER_MAIN-RUN-03_Audit.ps1`  
**Problem:** Die Funktion `Test-ObjectProperty` wird in Zeile 33 (`$_.PSObject.Properties.Name -contains "agent_type"`) verwendet, aber sie ist **nicht** in `autpilot-prompts.ps1` oder einem geladenen Modul definiert.

**Hinweis:** `Test-ObjectProperty` ist in `planning-utils.ps1` definiert (ZEILE 1-15), das in `autopilot.ps1` geladen wird, aber **nicht** in den ROUTER-Skripten.

**Fix:** Füge in die ROUTER-Skripte am Anfang hinzu:

```powershell
. (Join-Path $PSScriptRoot "../lib/planning-utils.ps1")
```

---

### 2.2 [MEDIUM] `autopilot.ps1` - `Write-Host` Overwrite kann zu Log-Latenz führen

**Datei:** `autopilot.ps1`  
**Linien:** 37-74

**Problem:** Die benutzerdefinierte `Write-Host`-Funktion (ZEILE 37) schreibt **synchron** in die Log-Datei. Bei hohem Durchsatz (z.B. 100+ SUB-RUNs pro Stunde) kann dies zu Latenz führen.

**Evidenz:**

```powershell
Add-Content -Path $liveLogPath -Value "[$timestamp] $cleanMsg" -Encoding UTF8 -ErrorAction SilentlyContinue
```

**Empfehlung:** Log-Einträge **asynchron** schreiben oder Buffering (z.B. alle 10 Einträge flushen).

---

### 2.3 [MEDIUM] `SUB-RUN-04_MR-01_Planning__Delegation.ps1` - Doppelter Issue-Import

**Datei:** `src/runs/SUB-RUN/SUB-RUN-04_MR-01_Planning__Delegation.ps1`  
**Problem:** Die Funktion `Get-GitHubIssues` wird in `SUB-RUN-01_MR-01_Planning__DataSync.ps1`aufgerufen und dann in `SUB-RUN-04_MR-01_Planning__Delegation.ps1` **erneut**.

**Evidenz:**

```powershell
# IN DATA-SYNC:
$issues = Get-GitHubIssues -Repository $repo -Limit 50

# IN DELEGATION (ZEILE 12):
$issues = Get-GitHubIssues -Repository $repo -Limit 50
```

**Empfehlung:** Issues im `DataSync`-SUB-RUN laden und im `MainState` speichern, dann `Delegation` liest von `MainState.PlanningCandidates`.

---

### 2.4 [MEDIUM] `ROUTER_MAIN-RUN-01_Planning.ps1` - Issue-Zählung ist ungenau

**Datei:** `src/runs/ROUTER/ROUTER_MAIN-RUN-01_Planning.ps1`  
**Linien:** 33-43

**Problem:** Die Issue-Zählung berücksichtigt **nicht** die `include_labels` Filter, die in der Config definiert sind.

```powershell
$openIssues = @($issuesRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo })
$issuesCount = $openIssues.Count
```

Die echte Issue-Zahl für Strategy-Entscheidung sollte die **gefilterte** Liste sein.

**Fix:**

```powershell
$candidates = @($openIssues | Where-Object { ... (include/exclude logic) })
$issuesCount = $candidates.Count
```

---

## 3. OPTIMIERUNGSVORSCHLÄGE (6)

### 3.1 [OPT-01] SUB-RUN-Parallele Ausführung im Orchestrator

**Aktuell:** `Invoke-MainRun.ps1` führt SUB-RUNs **sequenziell** aus (ZEILE 55: `foreach ($subDef in $subRunDefinitions)`).

**Vorteil Parallele Ausführung:**

- Check&Doing-ROUTER hat 6 SUB-RUNs (SessionSync, JulesCheck, LocalAgentCheck, ReviewDispatch, JulesRefill, Housekeeping)
- Diese könnten **parallel** laufen, da sie keine gemeinsamen Ressourcen nutzen.

**Implementierung:**

```powershell
# Ersetze foreach-Block durch:
$jobs = @()
foreach ($subDef in $subRunDefinitions) {
    $jobs += Start-Job -ScriptBlock {
        param($subDef, $MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
        # ... SUB-RUN ausführen
    } -ArgumentList $subDef, $MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun
}
$jobs | Wait-Job | Receive-Job
```

**Risiko:** Beiparalleler Jules-Aufrufen könnte Quota-Limits überschritten werden. Empfehlung: **Max 3 parallele SUB-RUNs** mit Config-Steuerung.

---

### 3.2 [OPT-02] Config-basierter Retry-Mechanismus für PART-RUNs

**Aktuell:** PART-RUNs失败后直接记录错误，without retry.

**Vorschlag:** Config-Parameter `part_run_retry` hinzufügen:

```json
{
  "part_run_retry": {
    "max_attempts": 2,
    "delay_seconds": 5,
    "backoff_multiplier": 1.5
  }
}
```

**Nutzen:** Verhindert sofortigen FAIL bei transienten Fehlern (API-Timeouts, Jules-Fehler).

---

### 3.3 [OPT-03] Prometheus-Compliant Metrics für Dashboard

**Aktuell:** `autopilot.ps1` schreibt Status in `Write-Host` (Terminal).

**Vorschlag:** Jeder MAIN-SUB-RUN-PART-RUN-Start/Ende sendet ein Metric:

```
vorce_autopilot_run{run_type="MAIN",run_name="MAIN-RUN-01_Planning",status="completed"} 1
```

**Implementierung:** `var/metrics.txt` als Prometheus-Format schreiben.

---

### 3.4 [OPT-04] Memory Optimization als eigenständiger MAIN-RUN

**Aktuell:** Memory Optimization ist in `SUB-RUN-05_MR-01_Planning__Optimization.ps1` enthalten.

**Vorschlag:** `MAIN-RUN-05_MemoryOptimization.ps1` erstellen mit eigenem ROUTER.

**Nutzen:** Könnte **nachts** (z.B. alle 6 Std) laufen, statt bei jedem 3. Planning-Cycle.

---

### 3.5 [OPT-05] PART-RUN-Output Caching

**Aktuell:** PART-RUN-Ausgaben werden in `run_path/output.txt` gespeichert, aber bei erneutem Aufruf **nicht** wiederverwendet.

**Vorschlag:** Hash des Prompts berechnen und cache-key als `PART-RUN-output-{hash}.json` speichern.

**Nutzen:** Reduziert Token-Verbrauch bei wiederholten identical prompts.

---

### 3.6 [OPT-06] Dashboard Health Check mit Timeout

**Aktuell:** `Wait-AutopilotControlConsole` nutzt `Start-Sleep -Milliseconds 500`.

**Vorschlag:** Echtzeit-Status aktualisieren via WebSocket oder SignalR statt Polling.

**Nutzen:** Reduziert CPU-Last und verbessert UX (live Status Updates).

---

## 4. FEHLERHAFTE DATEIEN (Summary)

| Datei | Status | Beschreibung |
|-------|--------|--------------|
| `src/runs/ROUTER/ROUTER_MAIN-RUN-02_CheckAndDoing.ps1` | **CRITICAL** | `$QuotaRegistry` undefined variable |
| `src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__Triage.ps1` | **CRITICAL** | Prompt abgeschnitten (nur 25 Zeilen) |
| `src/runs/SUB-RUN/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync.ps1` | **CRITICAL** | State-File-Pfad falsch |
| `src/runs/SUB-RUN/SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1` | **CRITICAL** | Path Resolution Error |
| `src/runs/ROUTER/ROUTER_MAIN-RUN-03_Audit.ps1` | **MEDIUM** | `Test-ObjectProperty` undefined |

---

## 5. EMPFOHLENE REIHENFOLGE FÜR FIXES

| Priorität | Fix | Zeitaufwand |
|-----------|-----|-------------|
| 1 | QuotaRegistry in CheckAndDoing-Router hinzufügen | 5 min |
| 2 | Triage Prompt komplettieren | 30 min |
| 3 | SessionSync State-Path fixen | 10 min |
| 4 | MemoryMaintenance Path Resolution fixen | 10 min |
| 5 | Test-ObjectProperty importieren | 5 min |
| 6 | Parallel Execution (OPT-01) | 2 Std |
| 7 | PART-RUN Retry (OPT-02) | 1 Std |

---

## 6. ANHANG

### 6.1 Verzeichnisstruktur (Vorce-Autopilot_2.0)

```
Vorce-Autopilot_2.0/
├── autopilot.ps1              # Haupt-Loop (MAIN-RUN Trigger)
├── Start-Autopilot.ps1        # Dashboard + Backend Start
├── config/
│   └── autopilot-config.json  # Konfiguration (Intervalle, Labels)
├── src/
│   ├── lib/                   # Bibliotheken (state-manager, github-client, etc.)
│   ├── orchestrator/          # Invoke-MainRun.ps1 (Orchestrierer)
│   ├── runs/
│   │   ├── MAIN-RUN/          # MAIN-RUN-01...04
│   │   ├── ROUTER/            # Router-Skripte (dynamische SUB-RUN-Entscheidung)
│   │   └── SUB-RUN/           # SUB-RUN-01...06 (Task-Execution)
│   ├── phases/                # Phasen-Skripte (interval-stats.ps1)
│   ├── agents/                # Agenten-Prompts
│   └── workers/               # Worker-Skripte
└── var/
    ├── db/                    # active-sessions.json, pull-requests.json
    ├── log/                   # autopilot-live.log
    ├── run/                   # run-state.json Files
    └── tmp/                   # TMP-Files
```

### 6.2 Workflow-Graph (MAIN-RUN-01_Planning)

```
MAIN-RUN-01_Planning
├── ROUTER (ROUTER_MAIN-RUN-01_Planning.ps1)
│   ├── ✅ DataSync (always)
│   ├── ✅ Triage (always)
│   ├── 🔄 Strategy (if <3 issues)
│   └── ✅ Delegation (always)
│
├── SUB-RUN-01_DATA-SYNC
│   └── LoadIssues -> PlanningCandidates
│
├── SUB-RUN-02_TRIAGE
│   ├── CEO Re-Planning (w/ QA-Manager deliberation)
│   └── PR Merge Conflict Check
│
├── SUB-RUN-03_STRATEGY (optional)
│   └── Issue Prioritization
│
└── SUB-RUN-04_DELEGATION
    ├── Check candidates
    └── Delegate to Jules
```

---

**Ende des Berichts**
