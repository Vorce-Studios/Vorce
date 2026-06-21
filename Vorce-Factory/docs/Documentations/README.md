Benutzer-Doku (Kurz-Version)  
Vorce-Factory  
Ein modularer KI‑Orchestrator für das Vorce‑Studios‑Repository.  
Was macht das System?  
- 
Automatisierte Planung – sammelt Issues, filtert, erstellt Proposals via Dual‑Agent‑Deliberation und delegiert an Jules.
- 
Kontinuierliches Monitoring – prüft laufende Jules‑Sessions, PR‑Reviews und führt House‑Keeping‑Aufgaben aus.
- 
Audit‑Runs – führt Compliance‑Checks und überblickt System‑Health.
- 
Optimierung & Memory‑Management – analysiert Lauf‑Statistiken, räumt verwaiste Daten auf.
Wesentliche Komponenten  
Komponente	Aufgabe
autopilot.ps1	Guard‑Loop, setzt globale Pfade, Health‑Check, startet Orchestrator
Vorce‑Orchestrator.ps1	Selektiert überfällige Main‑Runs, baut ConfigBag, steuert Router & Sub‑Runs
src/lib/*	Bibliotheken: State‑Management, GitHub‑Client, Agent‑Runner, Quota‑Manager, Prompt‑Loader
src/runs/…	Main‑Runs, Router, Sub‑Runs, Part‑Runs (atomare Aktionen)
var/	Laufzeit‑Daten (Config, DB‑JSONs, Logs, Prompts, Run‑States)
web/Dashboard/	React/Vite‑Frontend, synchronisiert via WebSocket (sync-service.ps1)
test/	Validierungsskripte (Boot, DryRun, Planning, Start)
Arbeitsablauf (typisch)  
1. 
Start – .\Start-Autopilot.ps1 prüft var/‑Ordner, lädt Config & GlobalState, startet Guard‑Loop.  
2. 
Guard‑Loop – ruft Vorce‑Orchestrator.ps1 → Select‑NextMainRun.  
3. 
Router – liefert Liste von Sub‑Runs (z. B. DataSync, Triage…).  
4. 
Sub‑Run – definiert Part‑Runs, ruft RunEngine.ps1 zur parallelen Ausführung.  
5. 
Part‑Run – führt einzelne API‑Calls oder Agent‑Aufrufe aus.  
6. 
State‑Update – Ergebnisse werden in var/run-states/ und global-state.json geschrieben.  
7. 
Dashboard – WebSocket‑Server pusht Änderungen an das Frontend.
Konfiguration  
var/config/autopilot-config.json (Beispielauszug)  
{
  "repository": "Vorce-Studios/Vorce",
  "wake_intervals": {
    "planning_minutes": 120,
    "check_and_doing_minutes": 15,
    "audit_minutes": 60,
    "optimizer_minutes": 720,
    "memory_optimization_minutes": 60
  },
  "router_rules": {
    "MAIN-RUN-01_Planning": "src/runs/MAIN-RUN-01_Planning/Planning-Router.ps1",
    "MAIN-RUN-02_CheckAndDoing": "src/runs/MAIN-RUN-02_CheckAndDoing/CheckAndDoing-Router.ps1",
    "MAIN-RUN-03_Audit": "src/runs/MAIN-RUN-03_Audit/Audit-Router.ps1"
  },
  "jules": {
    "monitoring_refill_enabled": true
  },
  "fallback_chain": ["gemini_cli","claude_code","codex","kiro","copilot","cursor_agent","hermes"]
}
Alle Pfade sind relativ zu $global:VorceRoot.  
Nutzung  
Befehl
.\Start-Autopilot.ps1
.\autopilot.ps1 -DryRun
.\test\Test‑Boot.ps1
.\test\Test‑OrchestratorDryRun.ps1
.\test\Test‑PlanningRun.ps1
Monitoring & Logs  
Logs → var/log/autopilot_YYYYMMDD_HHmmss.log (StatusPrinter‑Format).  
Dashboard – öffne http://localhost:5173 (Vite‑Dev‑Server). Echtzeit‑Updates per WebSocket (Port 5174).  
Fehlersuche  
1. 
Keine Logs? – Prüfe, ob var/log/ existiert; Start‑Autopilot.ps1 legt es an.  
2. 
GlobalState‑Fehler – global-state.json darf nicht leer oder "null" sein; Test‑Boot.ps1 überprüft das.  
3. 
Quota‑Fehler – AgentRunner.ps1 gibt WARN‑Meldungen; prüfe var/db/quota-registry.json.
Hinweis: Alle Pfad‑ und Konfigurationsänderungen erfolgen ausschließlich über die oben beschriebenen globalen Variablen und das ConfigBag. Direktes Editieren von Skript‑Pfade‑Strings führt zu Instabilität und wird im Code vermieden.
