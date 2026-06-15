Entwickler‑Doku (Agent‑optimiert)  
Version 3.0‑NEW – Stand 2026‑06‑14  
1. Projekt‑Architektur  
Vorce-Autopilot_NEW/
├─ autopilot.ps1                 # Guard‑Loop, setzt globale Variablen
├─ Start‑Autopilot.ps1           # Bootstrapper, Health‑Check, startet Orchestrator
├─ src/
│  ├─ lib/
│  │  ├─ state/                 # StateManager.ps1 – global‑ und Run‑State I/O
│  │  ├─ engines/               # RunEngine.ps1, DeliberationEngine.ps1, QuotaManager.ps1
│  │  ├─ integrations/          # GitHubClient.ps1, AgentRunner.ps1, ApiClient.ps1
│  │  └─ utils/                 # StatusPrinter.ps1, PromptManager.ps1, ProjectManager.ps1, TriageUtils.ps1
│  ├─ tools/
│  │  └─ services/              # sync‑service.ps1 (WebSocket‑Dashboard‑Sync), jules‑monitor.ps1
│  ├─ orchestrator/
│  │  └─ Vorce‑Orchestrator.ps1 # Dispatcher, Scheduling, ConfigBag‑Erstellung
│  └─ runs/
│     ├─ MAIN‑RUN‑01_Planning/
│     │   ├─ Planning‑Router.ps1
│     │   └─ SUB‑RUNS/
│     │       ├─ SUB‑RUN‑01_…_DataSync/
│     │       │   ├─ SUB‑RUN‑01_…_DataSync.ps1
│     │       │   └─ PART‑RUNS/
│     │       └─ … (Triage, Strategy, Delegation)
│     ├─ MAIN‑RUN‑02_CheckAndDoing/
│     │   ├─ CheckAndDoing‑Router.ps1
│     │   └─ SUB‑RUNS/… (SessionSync, JulesCheck, …)
│     ├─ MAIN‑RUN‑03_Audit/
│     │   ├─ Audit‑Router.ps1
│     │   └─ SUB‑RUNS/… (ComplianceCheck, …)
│     ├─ MAIN‑RUN‑04_Optimizer/
│     │   └─ Optimizer‑Router.ps1
│     └─ MAIN‑RUN‑05_MemoryOptimization/
│         └─ MemoryOptimization‑Router.ps1
├─ var/
│  ├─ config/   (autopilot‑config.json, quota‑registry.json)
│  ├─ db/       (global‑state.json, github‑issues.json, …, proposals/)
│  ├─ log/
│  ├─ prompts/  (system/, jules/, phases/, deliberation/)
│  ├─ run‑states/
│  └─ tmp/
└─ test/ … (Boot, DryRun, Planning, StartProcess)
2. Globale Variablen (immer gesetzt in autopilot.ps1)  
$global:VorceRoot = $PSScriptRoot
$global:VarDir    = Join-Path $global:VorceRoot "var"
$global:SrcDir    = Join-Path $global:VorceRoot "src"
$global:LibDir    = Join-Path $global:SrcDir "lib"
Alle Module benutzen ausschließlich $global:VarDir und $global:LibDir für Pfade – nie $PSScriptRoot.  
3. ConfigBag‑Pattern  
Der Orchestrator baut einmalig ein Hashtable ConfigBag:
$ConfigBag = @{
    VorceRoot     = $global:VorceRoot
    VarDir        = $global:VarDir
    SrcDir        = $global:SrcDir
    LibDir        = $global:LibDir
    Config        = $Config            # aus var/config/autopilot-config.json
    GlobalState   = $GlobalState       # aus var/db/global-state.json
    QuotaRegistry = $QuotaRegistry
    DryRun        = $DryRun
}
Alle Router, Sub‑Runs und Part‑Runs erhalten -ConfigBag $ConfigBag als ersten Parameter.  
4. Einheitliche Signaturen  
Typ	Signatur
Router	param([hashtable]$ConfigBag, [object]$MainState)
Sub‑Run	param([hashtable]$ConfigBag, [object]$ParentState)
Part‑Run	param([hashtable]$ConfigBag, [string]$PartName) (implizit durch RunEngine)
Rückgabe:  
-
Router → Array von Hashtables {id; name; script}  
-
Sub‑Run → PSCustomObject mit .status & .results
5. Scheduling‑Logik (in Vorce‑Orchestrator.ps1)  
function Select-NextMainRun {
    param($GlobalState,$Config)
    $runs = @(
        @{Name="MAIN-RUN-01_Planning";   IntervalKey="planning_minutes"},
        @{Name="MAIN-RUN-02_CheckAndDoing"; IntervalKey="check_and_doing_minutes"},
        @{Name="MAIN-RUN-03_Audit";      IntervalKey="audit_minutes"},
        @{Name="MAIN-RUN-04_Optimizer";  IntervalKey="optimizer_minutes"},
        @{Name="MAIN-RUN-05_MemoryOptimization"; IntervalKey="memory_optimization_minutes"}
    )
    $now = Get-Date
    $best=$null;$bestOverdue=-1
    foreach($run in $runs){
        $interval = [int]$Config.wake_intervals.$($run.IntervalKey)
        $lastRun = $GlobalState.last_runs.$($run.Name) -as [datetime]
        $overdue = if($lastRun){($now-$lastRun).TotalMinutes-$interval}else{[int]::MaxValue}
        if($overdue -gt $bestOverdue){$best=$run;$bestOverdue=$overdue}
    }
    if($bestOverdue -gt 0){ $best.Name } else { $null }
}
Nur überfällige Main‑Runs werden ausgeführt.  
6. Orchestrator‑Workflow (Kurz)  
1.
Module laden über $global:LibDir.  
2.
Config & Quota aus $global:VarDir/config/.  
3.
GlobalState aus var/db/global-state.json.  
4.
ConfigBag bauen.  
5.
Select‑NextMainRun → $mainRunName.  
6.
Router des Main‑Runs ausführen → Sub‑Run‑Definitionen.  
7.
Für jede Sub‑Run  
-
Try / Catch → Fehler werden geloggt, aber Orchestrator fährt fort.  
-
Sub‑Run aufrufen mit -ConfigBag und $MainState.
8.
Main‑State‑Ergebnisse in var/run-states/ persistieren.  
9.
GlobalState.last_runs aktualisieren, speichern.
7. Fehler‑ und Retry‑Strategie  
-
Part‑Run – RunEngine fängt Exceptions, markiert Part als failed aber fährt parallel fort.
-
Sub‑Run – Try / Catch im Orchestrator, fügt Fehlermeldung zum Main‑State hinzu.
-
Main‑Run – Orchestrator‑Fehler führen zu ERROR‑Logeintrag, Autopilot‑Loop wartet das konfigurierte Intervall und startet neu.
8. Quota‑Management (QuotaManager.ps1)  
-
Test‑VorceQuota prüft: Provider‑Aktiv, nicht erschöpft, unter daily‑limit & daily‑budget, CLI‑Verfügbarkeit.  
-
Bei Fehler Write‑VorceStep … -Status "WARN" und Rückgabe $false.  
-
Register‑VorceQuotaUsage erhöht calls & estimated_cost_usd, schreibt last_synced_at.
9. Agent‑Aufruf (AgentRunner.ps1)  
if(-not (Test-VorceQuota -AgentName $AgentName -ModelTier $ModelTier)){
    Write-VorceStep "Quota exhausted" -Status "WARN"
    return $null
}
Register-VorceQuotaUsage -AgentName $AgentName -ModelTier $ModelTier
# Start‑Process mit CLI‑Befehl, sammle STDOUT/STDERR nach var/tmp/
Fallback‑Chain (gemini → claude → codex → kiro → copilot → cursor‑agent → hermes) wird in AgentRunner implementiert.  
10. Dashboard‑Sync (WebSocket)  
-
src/tools/services/sync-service.ps1 lauscht auf Port 5174.  
-
Bei jedem Save‑VorceGlobalState wird ein JSON‑Patch an verbundene Dashboard‑Clients gesendet.
11. Tests (unter test/)  
Test	Zweck
Test‑Boot.ps1	Verzeichnis‑/Modul‑Integrität, globale Variablen, Export‑Verbot
Test‑OrchestratorDryRun.ps1	Dry‑Run‑Modus, ConfigBag‑Keys, Main‑Run‑Auswahl
Test‑PlanningRun.ps1	End‑to‑End‑Durchlauf des Planning‑Flows, Existenz von Sub‑ & Part‑Runs
Test‑StartProcess.ps1	Grundlegende Startup‑Checks (autopilot, health‑check)
12. Dokumentations‑Workflow  
-
Die Entwickler‑Doku (dieses Dokument) wird als Agent-Doku.md im Projekt‑Root abgelegt.  
-
Die Benutzer‑Doku (nachfolgend) wird als README.md bereitgestellt.
