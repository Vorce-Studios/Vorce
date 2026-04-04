# Code Atlas

Dieses Verzeichnis enthält einen agentenorientierten Code-Atlas für das Repository.

## Ziel

Der Atlas ist die schnelle Such- und Kontextschicht für KI-Agenten. Er soll breite Dateiscans reduzieren und vor dem Öffnen vieler Dateien eine belastbare erste Orientierung liefern.

## Artefakte

- `code-atlas.json`: Strukturierte Datei- und Abhängigkeitsdaten für Agenten und Tools.
- `workspace.mmd`: Mermaid-Übersicht des Workspace auf Crate-Ebene.
- `crates/*.mmd`: Mermaid-Dateien je Crate mit lokalen Datei-Abhängigkeiten.
- `SUMMARY.md`: Kompakte menschenlesbare Zusammenfassung.

## Standard-Workflow für Agenten

1. Atlas aktualisieren: `python scripts/dev-tools/generate-code-atlas.py`
2. Zielgerichtet suchen: `python scripts/dev-tools/query-code-atlas.py "crate:vorce-core tag:evaluation"`
3. Erst danach konkrete Dateien öffnen.

## Beispielabfragen

- `python scripts/dev-tools/query-code-atlas.py "symbol:ModuleEvaluator"`
- `python scripts/dev-tools/query-code-atlas.py "tag:rendering crate:vorce-render"`
- `python scripts/dev-tools/query-code-atlas.py "path:module_eval used-by:orchestration"`
- `python scripts/dev-tools/query-code-atlas.py "midi osc"`

## Hinweise

- Mermaid ist hier nur die Visualisierungsschicht.
- Die eigentliche Query-Basis ist `code-atlas.json`.
- Die Daten sind heuristisch erzeugt und ersetzen bei Detailfragen nicht das Lesen der Ziel-Dateien.
- Auf GitHub wird der Atlas per Workflow `.github/workflows/CICD-MainFlow_Job05_CodeAtlas.yml` automatisch auf `main` aktualisiert.
