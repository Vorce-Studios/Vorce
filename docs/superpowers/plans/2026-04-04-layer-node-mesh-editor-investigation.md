# Layer Node Mesh Editor Investigation

## Goal

Klaeren, warum Layer-Nodes im Inspector aus Anwendersicht keinen verfuergbaren Mesh-Editor zeigen, obwohl der Mesh-Editor-Pfad im Code vorhanden ist.

## Current Findings

- Der Module-Canvas-Inspector routed `ModulePartType::Layer(...)` bereits in den Layer-Inspector:
  - `crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/layer.rs`
- `render_layer_ui(...)` ruft fuer `LayerType::Single` und `LayerType::Group` immer `mesh::render_mesh_editor_ui(...)` auf.
- `ModuleCanvas` startet bereits mit `LayerInspectorViewMode::MeshEditor`.
- Es gibt daher aktuell keinen kleinen statischen Defekt wie:
  - fehlender Match-Arm
  - fehlender Aufruf des Mesh-Editors
  - falscher Default fuer den Layer-Inspector-View-Mode

## Most Likely Problem Classes

1. Auswahl-/Kontextproblem:
   Der Inspector zeigt nicht den Modul-Part-Kontext, sondern faellt auf einen anderen Inspector-Kontext zurueck.

2. Sichtbarkeits-/Layoutproblem:
   Der Mesh-Editor ist vorhanden, aber in einer konkreten UI-Konstellation nicht sichtbar genug oder durch einen anderen Inspector-Bereich verdraengt.

3. Zustandsproblem:
   Der globale `layer_inspector_view_mode` oder die Selektion werden zwischen mehreren Layer-/Inspector-Kontexten nicht robust genug synchronisiert.

## Implementation Plan

1. Repro absichern
   - Einen klaren Repro fuer einen selektierten `ModulePartType::Layer` dokumentieren.
   - Dabei unterscheiden zwischen:
     - Module-Canvas Layer-Node
     - Legacy Layer Inspector

2. Inspector-Kontext instrumentieren
   - Temporare Logs fuer:
     - `active_module_id`
     - selektierte `part_id`
     - resultierenden `InspectorContext`
     - `LayerInspectorViewMode`

3. Sichtbarkeit absichern
   - Fuer Layer-Nodes einen expliziten Mesh-Editor-Abschnitt mit sichtbarer Ueberschrift und klarer Fallback-Meldung erzwingen.
   - Falls noetig: Preview-/Mesh-Toggle pro selektiertem Layer statt global speichern.

4. Regression absichern
   - Mindestens einen kleinen UI-/State-Test oder einen gezielten Debug-Repro hinterlegen, damit der Inspector fuer Layer-Nodes nicht erneut auf einen falschen Kontext faellt.

## Acceptance Criteria

- Wenn im Module Canvas ein Layer-Node selektiert ist, erscheint im rechten Inspector immer ein klar erkennbarer Mesh-Editor-Bereich.
- Der Inspector faellt in diesem Fall nicht still auf den Legacy-Layer- oder Output-Kontext zurueck.
- Preview und Mesh-Editor sind fuer Layer-Nodes nachvollziehbar umschaltbar.
- Die Auswahl eines anderen Layer-Nodes fuehrt nicht zu einem "leeren" Inspector ohne Mesh-Konfigurationsmoeglichkeit.
