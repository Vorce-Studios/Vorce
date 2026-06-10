# VORCE-AUTOPILOT 2.0 - ARCHITEKTUR-DOKUMENTATION

## 1. Übersicht
Vorce-Autopilot 2.0 führt eine baumartige, hierarchische Orchestrierung ein, die die bisherige flache "Wakeup-Skript" Struktur ersetzt. Ziel ist eine höhere Effizienz, bessere Fehlerisolierung und granulare Steuerung der KI-Ressourcen.

## 2. Kernkomponenten

### 2.1 Der Orchestrator (`src/orchestrator/Invoke-MainRun.ps1`)
Der zentrale Einstiegspunkt für jede Phase (z.B. Planning, Monitoring).
- Erstellt eine eindeutige Run-ID.
- Initialisiert die Verzeichnisstruktur für Logs und Status in `var/run/`.
- Nutzt den Router, um die auszuführenden Sub-Runs zu bestimmen.
- Verwaltet das Error Handling auf Phase-Ebene.

### 2.2 Der Router (`src/router/Invoke-MainRunRouter.ps1`)
Die "Intelligenz" zur Auswahl der notwendigen Aktionen.
- Evaluiert den aktuellen Systemzustand.
- Bestimmt dynamisch, welche Sub-Runs (z.B. "ContextGathering", "TaskDelegation") aktiv sein müssen.
- Ermöglicht Token-Einsparungen durch das Überspringen nicht benötigter Logik.

### 2.3 Main-Runs, Sub-Runs & Part-Runs
- **Main-Run**: Eine vollständige Phase (Planning, Monitoring, Audit).
- **Sub-Run**: Ein funktionaler Block innerhalb eines Main-Runs (z.B. "PR-Check").
- **Part-Run**: (Zukünftig) Kleinteilige Aktionen innerhalb eines Sub-Runs.

### 2.4 State Management (`src/lib/run-state-manager.ps1`)
Ein neues, hierarchisches State-System.
- Jeder Run (Main/Sub) hat seine eigene `.json` State-Datei.
- Speichert Startzeit, Endzeit, Status, Fehler und generierte Artefakte.
- Ermöglicht präzises Tracking der Effizienz und Fehleranalyse.

## 3. Datenfluss
1. `autopilot.ps1` ruft `Invoke-MainRun -RunName "Planning"` auf.
2. `Invoke-MainRun` fragt den `Router` nach Sub-Runs.
3. Der `Router` gibt eine Liste von Skriptpfaden zurück.
4. `Invoke-MainRun` führt die Sub-Runs sequentiell aus und isoliert Fehler.
5. Ergebnisse werden in `var/run/{RunName}/` persistiert.

## 4. Vorteile der neuen Struktur
- **Transparenz**: Jede Aktion hinterlässt einen eindeutigen JSON-State.
- **Resilienz**: Ein Fehler in einem Sub-Run (z.B. PR-Check) bringt nicht den gesamten Planning-Lauf zum Absturz.
- **Effizienz**: Durch den Router werden nur die Sub-Runs ausgeführt, die für den aktuellen Zustand relevant sind.
- **Wartbarkeit**: Klare Trennung von Orchestrierung (Wie wird ausgeführt) und Logik (Was wird ausgeführt).
