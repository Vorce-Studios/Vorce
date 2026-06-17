# Implementierungsplan: Dashboard- & System-Prompt-Optimierung (Erweitert)

## Ziel
Vollständige Modernisierung des Dashboards für die neue Run-Hierarchie und ein lückenloses, standardisiertes System-Prompt-Framework für maximale Autonomie und Token-Effizienz.

---

## Phase 1: Dashboard UI/UX & Real-Time Sync

### Aufgabe 1.1: Backend-Watcher & useWebSocket Refactoring
**Ziel:** Echtzeit-Datenfluss ohne manuelles Neuladen.

**Text-Prompt für Agent:**
> Optimiere `web/Dashboard/src/hooks/useWebSocket.ts` und die Datenanbindung.
> 1. Erstelle einen "Watcher"-Service (z.B. ein einfaches Node.js oder PowerShell Skript), der Änderungen in `var/db/` und `var/run-states/` erkennt und per WebSocket ans Frontend pusht.
> 2. Passe `useWebSocket` so an, dass es diese Signale verarbeitet und nur die betroffenen State-Fragmente aktualisiert.
> 3. Implementiere eine visuelle "Last Sync" Anzeige im Dashboard-Header.

### Aufgabe 1.2: Hierarchische Run-Visualisierung
**Ziel:** Transparente Darstellung von Main-, Sub- und Part-Runs.

**Text-Prompt für Agent:**
> Überarbeite die Hauptansicht in `web/Dashboard/src/App.tsx`.
> 1. Ersetze die flache Liste durch eine hierarchische Tree-View Komponente.
> 2. Jede Ebene (Main/Sub/Part) soll einen Status-Indikator (Farbe/Icon) und einen Link zum jeweiligen JSON-State-File haben.
> 3. Implementiere einen "Log-Monitor" Bereich, der die neuesten Zeilen aus `var/log/autopilot.log` in Echtzeit streamt.

---

## Phase 2: Prompt-Engine & Snippet-System

### Aufgabe 2.1: Modulares Snippet-Management
**Ziel:** Vermeidung von Redundanz durch wiederverwendbare Prompt-Bausteine.

**Text-Prompt für Agent:**
> Erweitere `src/lib/utils/PromptManager.ps1`.
> 1. Füge eine Funktion `Get-VorcePromptSnippet` hinzu, die Dateien aus `var/prompts/shared/snippets/` lädt.
> 2. Implementiere eine automatische Ersetzung: Wenn ein Prompt den Tag `[[SNIPPET:Name]]` enthält, soll dieser durch den Inhalt des entsprechenden Snippets ersetzt werden.
> 3. Erstelle Standard-Snippets für: `Dashboard-Link-Context`, `Quota-Rules`, `Git-Safety-Mandates`.

---

## Phase 3: System & Run Prompt Standardisierung

### Aufgabe 3.1: CEO-Orchestrator & Policy Audit
**Ziel:** Schärfung der "Rules of Engagement".

**Text-Prompt für Agent:**
> Überarbeite `var/prompts/system/SYSTEM-PROMPT-01_Autopilot__CEO-Orchestrator.md` und `SYSTEM-PROMPT-02_Autopilot__Dashboard-Context-Policy.md`.
> 1. Nutze ein striktes Format: # Persona | # Context | # Tasks | # Constraints.
> 2. Definiere klare Priorisierungskriterien für die Task-Auswahl.
> 3. Stelle sicher, dass der Agent instruiert wird, das Dashboard aktiv als "Source of Truth" für den Systemstatus zu nutzen.

---

## Phase 4: Implementierung fehlender Run-Prompts

### Aufgabe 4.1: Erstellung der Phasen-Prompts
**Ziel:** Spezifische Anweisungen für Triage, Strategy und Delegation.

**Text-Prompt für Agent:**
> Erstelle/Überarbeite folgende Prompts in `var/prompts/runs/`:
> 1. `RUN-PROMPT-Triage.md`: Fokus auf Labeling-Logik und Priorisierung nach Schweregrad.
> 2. `RUN-PROMPT-Strategy.md`: Fokus auf die Deliberation-Technik (Proposal -> Critique -> Synthesis).
> 3. `RUN-PROMPT-Delegation.md`: Fokus auf die Erstellung klarer Instruktionen für Sub-Agenten (Jules).
> 4. `RUN-PROMPT-Review.md`: Fokus auf Compliance-Checks und Code-Qualität.
> Nutze in allen Prompts die `{{Variable}}` Syntax für dynamische Daten.

---

## Phase 5: Validierung & Token-Check

### Aufgabe 5.1: Prompt-Volumen-Optimierung
**Ziel:** Maximale Information bei minimalen Kosten.

**Text-Prompt für Agent:**
> Analysiere die fertigen Prompts auf Token-Effizienz.
> 1. Kürze narrative Erklärungen ("You are a helpful assistant...") zugunsten von direkten Direktiven.
> 2. Verifiziere, dass keine zwei Prompts identische, großflächige Anweisungen enthalten (Verschiebe diese in Phase 2 Snippets).
> 3. Teste den `PromptManager` mit einem Mock-Datensatz auf fehlerfreie Zusammenstellung.
