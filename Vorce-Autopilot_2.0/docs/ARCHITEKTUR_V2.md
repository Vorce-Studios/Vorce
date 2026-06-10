# Vorce-Autopilot 2.0 - Architektur & Workflows

Dieses Dokument beschreibt die neuen Strukturen und Abläufe des Vorce-Autopiloten in Version 2.0.

## 1. Zentrale Änderungen (Refactoring)

- **Terminology-Migration:** 
  - *CEO Alpha* -> **CEO** (Strategischer Entscheider)
  - *CEO Beta* -> **QA-Manager** (Kritische Instanz & Auditor)
- **Hierarchischer Orchestrator:** Einführung von `Invoke-MainRun` und `Invoke-MainRunRouter`. Phasen (Planning, Monitoring, Audit) sind keine monolithischen Funktionen mehr, sondern dynamische Sequenzen von *Sub-Runs*.
- **Data-Driven Routing:** Die Prozesslogik wird über `router_rules` in der `autopilot-config.json` gesteuert.
- **Staging-Audit:** Erweiterte "Remediate before Escalate"-Logik im System-Audit.

## 2. System-Architektur

```mermaid
graph TD
    Start[autopilot.ps1] --> Init[Initialize-AutopilotState]
    Init --> MainLoop{Main Loop}
    
    subgraph Orchestrator [Hierarchischer Orchestrator]
        MainLoop -->|Planning Interval| Planning[Invoke-MainRun: Planning]
        MainLoop -->|Monitoring Interval| Monitoring[Invoke-MainRun: Monitoring]
        
        Planning --> RouterP[Invoke-MainRunRouter]
        RouterP --> SR_P1[SR-01_ContextGathering]
        RouterP --> SR_P2[SR-00_LegacyPlanningFallback]
        
        Monitoring --> RouterM[Invoke-MainRunRouter]
        RouterM --> SR_M1[SR-01_SystemHealthCheck]
        RouterM --> SR_M2[SR-00_LegacyMonitoringFallback]
    end

    subgraph Deliberation [Dual-CEO Deliberation]
        SR_P2 --> Delib[Invoke-Deliberation]
        Delib --> Proposal[Phase 1: CEO Proposal]
        Proposal --> Critique[Phase 2: QA-Manager Critique]
        Critique --> Synthesis[Phase 3: CEO Synthesis]
    end

    subgraph State [State Management]
        SR_P1 --> VarDB[(var/db/active-sessions.json)]
        SR_P2 --> VarDB
        Monitoring --> VarDB
        VarDB --> Dashboard[React Dashboard]
    end
```

## 3. Workflows

### 3.1 Planning Workflow (V2.0)
1. **Context Gathering:** Synchronisiert GitHub Issues und Jules-Sessions.
2. **Analysis:** CEO evaluiert die aktuelle Lage.
3. **Deliberation:** Bei komplexen Aufgaben (z.B. Re-Planning nach Fehlern) wird der QA-Manager zur Gegenprüfung hinzugezogen.
4. **Delegation:** Aufgaben werden an Jules oder andere Agenten delegiert.

### 3.2 Audit & Remediation Workflow
1. **Audit Wake-Up:** Der QA-Manager scannt das System.
2. **Autonomous Remediation:** Wenn ein Problem gefunden wird, generiert der QA-Manager einen PowerShell-Befehl zur Behebung.
3. **Execution:** Der Autopilot führt den Befehl autonom aus.
4. **Escalation:** Erst wenn die Reparatur fehlschlägt, wird eine `decision_pending` (Alert) im Dashboard erstellt.
5. **User Interaction:** Der User hat nun im Dashboard drei Optionen:
   - *Befehl erneut ausführen* (Manuelle Remediation).
   - *CEO Sondersession anfordern* (Eskalation an CEO).
   - *Schließen/Ignorieren* (Abschluss des Alerts).

## 4. Dashboard Neuerungen

- **Router Control:** Sub-Runs können in den Einstellungen einzeln aktiviert/deaktiviert werden.
- **Enhanced Alerts:** Klare Unterscheidung zwischen Problem, Reparaturversuch und Eskalationsstatus.
- **Protocol View:** Detaillierte Einsicht in die Dual-CEO Deliberation-Runden.

---
*Vorce-Autopilot 2.0 - Build 2026-06-10*
