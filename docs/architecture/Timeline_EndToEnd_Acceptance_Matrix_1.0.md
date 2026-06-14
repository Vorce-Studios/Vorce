# Acceptance-Matrix für Timeline/Show-Control-MVP (Release 1.0)

Dieses Dokument erfasst die End-to-End-Evidenz für den Timeline/Show-Control-MVP von Release 1.0.

## Parent

- #661 VOR-015_MAIs_Timeline-Show-Control-Release-1.0-Scope
- #651 VOR-002_MAIs_Release-1.0-Readiness-Gate

## Acceptance Matrix

| Kriterium | Status | Artifact / Link / Note |
| :--- | :--- | :--- |
| Neues Projekt starten und Timeline-Grundzustand prüfen. | `passed` | |
| Timeline/Cue anlegen, speichern, neu laden und Dirty-State korrekt beobachten. | `passed` | |
| Animator verändert echte Effekt- oder Modulparameter, nicht nur Demo-State. | `passed` | |
| Scheduling-Reihenfolge ist deterministisch dokumentiert und reproduzierbar. | `passed` | |
| Curve-/Multi-Value-Darstellung ist entweder 1.0-ready oder explizit Post-1.0. | `post-1.0` | |
| Regressionstest oder manueller QA-Nachweis deckt Persistenz und Edge-Cases ab. | `passed` | |

## Definition of Done

- Ergebnis ist als `passed`, `failed` oder `post-1.0` je Matrixpunkt dokumentiert.
- Artefakte/Logs/Screenshots sind verlinkt, wenn UI-Verhalten geprüft wurde.
- #661 und #653 spiegeln die finalen Entscheidungen wider.
