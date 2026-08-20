# Implementierungsplan: Vorce-Factory Output- & Struktur-Optimierung

## Ziel
Verbesserung der Terminal-Visualisierung der Run-Hierarchie (Main/Sub/Part) und Optimierung der Ausführungsstruktur für höhere Effizienz (Parallelisierung) und geringeren Token-Verbrauch.

---

## Phase 1: Terminal-UI Upgrade (StatusPrinter.ps1)

### Aufgabe 1.1: Redesign der Status-Ausgaben
**Ziel:** Einführung einer klaren hierarchischen Struktur durch Einrückungen, Icons und Box-Elemente.

**Text-Prompt für Agent:**
> Überarbeite `src/lib/utils/StatusPrinter.ps1`.
> 1. Erweitere `Write-VorceHeader` um einen optionalen Untertitel und eine breitere Box.
> 2. Implementiere `Write-VorceRunStart` und `Write-VorceRunEnd` für Main-, Sub- und Part-Ebenen. Diese sollen unterschiedliche Einrückungstiefen (Indentation) und Icons verwenden.
> 3. Optimiere `Write-VorceStep`: Füge eine Status-Spalte hinzu, die fest positioniert ist, damit Fortschritte (z.B. [ RUN ] -> [ OK ]) besser ins Auge springen.
> 4. Nutze ANSI-Farben konsistent: Main-Run (Cyan), Sub-Run (Yellow), Part-Run (White).
> 5. Stelle sicher, dass Zeitstempel dezent am Rand stehen.

---Done

## Phase 2: Live-Streaming & Hierarchie-Integration (RunEngine & Orchestrator)

### Aufgabe 2.1: Live-Output aus Hintergrund-Jobs
**Ziel:** Echtzeit-Anzeige der Ausgaben von Part-Runs im Hauptterminal.

**Text-Prompt für Agent:**
> Modifiziere `src/lib/engines/RunEngine.ps1` in der Funktion `Invoke-VorceSubRunParallel`.
> 1. Ändere die Job-Loop so, dass `Receive-Job -Job $job` innerhalb der `while`-Schleife aufgerufen wird, um Ausgaben (Host-Messages) sofort anzuzeigen.
> 2. Implementiere ein "Spinning"-Icon für laufende Jobs.
> 3. Stelle sicher, dass Fehlermeldungen aus Jobs präzise dem jeweiligen Part zugeordnet werden.

### Aufgabe 2.2: Transparente Orchestrierung
**Ziel:** Der Orchestrator zeigt einen klaren "Execution Plan" vor dem Start.

**Text-Prompt für Agent:**
> Optimiere `src/orchestrator/Vorce-Orchestrator.ps1`.
> 1. Füge vor dem Start der Sub-Run-Schleife eine Übersicht ein, die alle geplanten Sub-Runs und deren Part-Counts auflistet.
> 2. Zeige am Ende des Main-Runs eine tabellarische Zusammenfassung: `Sub-Run | Status | Dauer | Ergebnis`.

---Done

## Phase 3: Run-Struktur & Token-Optimierung

### Aufgabe 3.1: Parallelisierung der Strategy-Phase
**Ziel:** Parallelverarbeitung mehrerer Issues statt sequenzieller Bearbeitung.

**Text-Prompt für Agent:**
> Refactor `src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/SUB-RUN-03_MR-01_Planning__Strategy.ps1`.
> 1. Erstelle für JEDES Issue in `triaged-issues.json` einen eigenen Part-Run im Array `$PartRuns`.
> 2. Übergib die `IssueNumber` als Argument an den Part-Run.
> 3. Passe den Part-Run `PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1` so an, dass er die `IssueNumber` aus den `$Arguments` liest.

### Aufgabe 3.2: Token-Effizienz (Prompt Slimming)
**Ziel:** Reduzierung des Kontext-Volumens.

**Text-Prompt für Agent:**
> Optimiere die Variablenübergabe in `PART-RUN-01_CreateProposal.ps1`.
> 1. Entferne redundante Pfadangaben und System-Anweisungen aus dem Context-Prompt, die für die reine Proposal-Erstellung nicht nötig sind.
> 2. Implementiere eine Logik, die nur die für das spezifische Issue relevanten Code-Snippets (falls vorhanden) in den Prompt lädt.

---Done

## Phase 4: Validierung

### Aufgabe 4.1: End-to-End Test
**Ziel:** Verifizierung der UI und Funktionalität.

**Text-Prompt für Agent:**
> Führe `test/Test-OrchestratorDryRun.ps1` aus.
> 1. Überprüfe die visuelle Hierarchie im Terminal.
> 2. Bestätige, dass Parallel-Jobs korrekt geloggt werden.
> 3. Verifiziere die JSON-Handoffs in `var/run-states/`.

---Done