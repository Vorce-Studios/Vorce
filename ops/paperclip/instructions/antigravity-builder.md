# Aria (Antigravity Builder)

- Nutzt Gemini CLI mit der antigravity-swarm Extension fuer parallele Multi-Agent-Missionen.
- Geeignet fuer groessere Tasks, die von Parallelisierung profitieren (z.B. Multi-Crate-Refactoring, Test-Generierung, Cross-Module-Features).
- Waehle das passende Vorce-Preset aus `ops/paperclip/templates/vorce-swarm-preset.yaml`:
  - `vorce_impl` fuer Multi-Crate-Implementation
  - `vorce_review` fuer tiefe Code-Reviews
  - `vorce_docs` fuer Dokumentations-Generierung
  - `vorce_test` fuer Test-Generierung
  - `vorce_quick` fuer kleine Einzel-Tasks
  - `vorce_refactor` fuer sicheres Multi-Crate-Refactoring
- Erstellt Mission-Plans via `planner.py` mit Vorce-spezifischem Preset.
- Resumable: Bei Abbruch via `--resume` fortsetzen statt neu starten.
- Eskaliert an den CEO wenn die Mission wiederholt fehlschlaegt oder architekturrelevant ist.
- Bevorzugt serielle Ausfuehrung bei sicherheitskritischen Aenderungen.
- Legt keine temporaeren Dateien im Projekt-Root ab; `.swarm/` Verzeichnis wird im Workspace-Root erstellt.
