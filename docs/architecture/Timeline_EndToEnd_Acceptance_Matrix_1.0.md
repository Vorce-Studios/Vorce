# Acceptance-Matrix für Timeline/Show-Control-MVP (Release 1.0)

Dieses Dokument erfasst die End-to-End-Evidenz für den Timeline/Show-Control-MVP von Release 1.0.

## Parent
- #661 VOR-015_MAIs_Timeline-Show-Control-Release-1.0-Scope
- #651 VOR-002_MAIs_Release-1.0-Readiness-Gate

## Acceptance Matrix

| Kriterium | Status | Artifact / Link / Note |
| :--- | :--- | :--- |
| Neues Projekt starten und Timeline-Grundzustand prüfen. | `partial` | Timeline-Basis- und Modus-Tests bestehen; ein verlinkter UI-Startnachweis fehlt in dieser Matrix. |
| Timeline/Cue anlegen, speichern, neu laden und Dirty-State korrekt beobachten. | `open` | #96 und #103 bleiben offen. #737 deckt nur einen Teil des Testpfads ab. |
| Animator verändert echte Effekt- oder Modulparameter, nicht nur Demo-State. | `open` | #98 bleibt offen; `crates/vorce/src/app/loops/logic.rs` verwirft die erzeugten Updates aktuell in `_param_updates`. |
| Scheduling-Reihenfolge ist deterministisch dokumentiert und reproduzierbar. | `partial` | Deterministische Tests bestehen, die vollständige Semantik aus #101 ist noch nicht abgeschlossen. |
| Curve-/Multi-Value-Darstellung ist entweder 1.0-ready oder explizit Post-1.0. | `post-1.0` | #99 bleibt als Post-1.0-Feature offen und blockiert den 1.0-Scope nicht. |
| Regressionstest oder manueller QA-Nachweis deckt Persistenz und Edge-Cases ab. | `partial` | Vorhandene Timeline-Tests bestehen; die vollständige Matrix aus #103 ist noch offen. |

## Definition of Done

- Ergebnis ist als `passed`, `failed` oder `post-1.0` je Matrixpunkt dokumentiert.
- Artefakte/Logs/Screenshots sind verlinkt, wenn UI-Verhalten geprüft wurde.
- #661 und #653 spiegeln die finalen Entscheidungen wider.

Solange Einträge `open` oder `partial` sind, ist die Matrix nicht abgeschlossen.
