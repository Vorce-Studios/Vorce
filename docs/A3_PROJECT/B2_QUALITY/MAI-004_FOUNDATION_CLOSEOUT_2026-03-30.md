# MAI-004 Foundation Migration Local Closeout

Stand: 2026-03-31

## Zweck

Dieses Dokument ersetzt sowohl den voreiligen Closeout-Claim vom 2026-03-30 als auch das reine Reassessment. Es beschreibt den fachlich gegengeprueften lokalen Workspace-Stand nach Abschluss der noch offenen Implementierungsarbeiten fuer die MAI-004-Subissues.

Wichtig: Dieses Dokument beschreibt technische Fertigstellung im aktuellen Workspace. GitHub-Issues oder offene Jules-/PR-Zustaende gelten dadurch noch nicht automatisch als remote abgeschlossen, solange der Code nicht gepusht und gemergt ist.

## Gesamtstatus

- Die zuvor noch offenen Code-Luecken aus `#56`, `#57`, `#60`, `#65`, `#66` und `#68` sind im lokalen Workspace umgesetzt.
- Die bereits frueher gelandeten Arbeiten aus `#62`, `#63`, `#64` und `#67` wurden im aktuellen Code erneut fachlich gegengeprueft.
- Aus technischer Sicht ist MAI-004 lokal jetzt in einem Zustand, in dem die Subissues nach Remote-Integration sauber auf `Done` gesetzt werden koennen.

## Status je Subissue

### `#56` Schema-Driven Inspector Completion

Status: `Done lokal`

- Output-, Source- und Hue-Inspector folgen jetzt einem konsistenteren Capability-Vertrag.
- Nicht wirksame Projector-Controls sind klar gegatet, insbesondere `extra_preview_window`.
- Der Effect-Inspector erlaubt keine Rueckmutation mehr auf Effekt-Typen ohne aktive Runtime-Unterstuetzung; alte Nodes bleiben sichtbar, aber klar als gated markiert.
- Trigger-Mapping bleibt ueber das bestehende Schema-Gating begrenzt.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/inspector/output.rs`
- `crates/vorce-ui/src/editors/module_canvas/inspector/source.rs`
- `crates/vorce-ui/src/editors/module_canvas/inspector/effect.rs`
- `crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs`
- `crates/vorce-ui/src/editors/module_canvas/inspector/hue.rs`

### `#57` Runtime Render Queue Feature Parity

Status: `Done lokal`

- Color calibration laeuft wieder im aktiven Post-Processing-Pfad statt still ignoriert zu werden.
- Fehlerhafte `RuntimeRenderQueueItem`s mit `DiagnosticSeverity::Error` werden sauber uebersprungen statt den gesamten Renderpfad zu destabilisieren.
- Blend-Mode-Diagnostik wird nur noch fuer wirklich nicht wirksame Modi erzeugt.
- Masks bleiben bewusst nicht halbverdrahtet: sie sind im Katalog/Add-Node bereits verborgen und im Inspector nun explizit read-only gegatet, waehrend die Runtime die Nicht-Unterstuetzung weiterhin diagnostiziert.

Relevante Codepfade:

- `crates/vorce/src/app/loops/render/content.rs`
- `crates/vorce/src/app/loops/render/mod.rs`
- `crates/vorce/src/app/loops/render/previews.rs`
- `crates/vorce/src/orchestration/evaluation.rs`
- `crates/vorce-ui/src/editors/module_canvas/inspector/layer.rs`

### `#60` Node Fault Isolation and Diagnostics

Status: `Done lokal`

- Projector-/Window-Synchronisation behandelt Teilfehler jetzt lokal pro Output und laeuft fuer andere Outputs weiter.
- Stale Outputs und Windows werden deterministisch entfernt.
- Hue-Dispatch aus der Evaluation ist fault-isolated und loggt Ausfaelle pro Node throttled statt die App hochzureissen.

Relevante Codepfade:

- `crates/vorce/src/orchestration/outputs.rs`
- `crates/vorce/src/window_manager.rs`
- `crates/vorce/src/orchestration/evaluation.rs`

### `#62` Trigger Event Nodes Migration

Status: `Im Code bestaetigt`

- Event-Trigger-Pfade fuer `Beat`, `Random`, `Fixed`, `Midi`, `Shortcut` und `AudioFFT` sind im aktuellen Code sichtbar und konsistent.
- In diesem Abschlusslauf war hier keine weitere Implementierung mehr noetig.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/inspector/trigger.rs`

### `#63` Trigger Signal Nodes Migration

Status: `Im Code bestaetigt`

- Signal-/Preview-Pfade fuer `Midi` und `AudioFFT` sind fachlich im Code verankert.
- Die Auswertung in `vorce-core` ist fuer den aktuellen Scope ausreichend vorhanden.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/inspector/trigger.rs`
- `crates/vorce-core/src/module_eval/evaluator/triggers.rs`

### `#64` Media File Source Nodes Migration

Status: `Im Code bestaetigt`

- Die Media-Familien `MediaFile`, `VideoUni`, `ImageUni`, `VideoMulti` und `ImageMulti` sind im Inspector und in den aktiven Runtime-/Traversal-Pfaden konsistent sichtbar.
- In diesem Abschlusslauf war hier keine weitere Implementierung mehr noetig.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/inspector/source.rs`
- `crates/vorce/src/orchestration/media.rs`
- `crates/vorce-core/src/module_eval/evaluator/traversal.rs`

### `#65` Layer and Projector Nodes Migration

Status: `Done lokal`

- `LayerType::Group` ist im Inspector wie ein echter Layer bearbeitbar.
- `LayerType::All` bleibt bewusst sichtbar, aber sauber deaktiviert und als nicht renderbar gekennzeichnet.
- Projector-Nodes synchronisieren jetzt `name`, `hide_cursor`, `target_screen` und Aufloesung sauber in den Window-Lifecycle.
- Preview-Panel-Nutzung bleibt ueber das bestehende `show_in_preview_panel`-Modell konsistent.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/inspector/layer.rs`
- `crates/vorce/src/orchestration/outputs.rs`
- `crates/vorce/src/window_manager.rs`
- `crates/vorce/src/app/ui_layout.rs`

### `#66` Bevy Source Nodes Migration

Status: `Done lokal`

- `Bevy3DModel` ist im Katalog/Add-Node sichtbar.
- Der passende Inspector ist fuer Pfad, Tint, Unlit, Transform sowie Outline implementiert.
- Nicht stabile Bevy-/External-IO-Faelle bleiben ueber Capability-Gating getrennt sichtbar statt halbverdrahtet.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/draw/add_node.rs`
- `crates/vorce-ui/src/editors/module_canvas/utils/catalog.rs`
- `crates/vorce-ui/src/editors/module_canvas/inspector/source.rs`

### `#67` External IO Nodes Gating and Migration

Status: `Im Code bestaetigt`

- Shader, LiveInput, NDI und Spout folgen im Katalog/Add-Node/Inspector weiter dem Capability-Gating.
- Die Runtime-Diagnostik bleibt fuer bewusst nicht aktivierte Pfade konsistent.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/inspector/capabilities.rs`
- `crates/vorce-ui/src/editors/module_canvas/utils/catalog.rs`
- `crates/vorce-ui/src/editors/module_canvas/draw/add_node.rs`
- `crates/vorce/src/orchestration/evaluation.rs`

### `#68` Hue Node Model Runtime Gating and Spatial Editor

Status: `Done lokal`

- Die Hue-Familie hat jetzt einen echten node-spezifischen Inspector fuer `SingleLamp`, `MultiLamp` und `EntertainmentGroup`.
- `SourceCommand::HueOutput` ist in den Runtime-Loop verdrahtet.
- Hue-Fehler bleiben lokal isoliert und werden pro Node geloggt.
- Der vorhandene Spatial-Editor bleibt fuer `HueMappingMode::Spatial` aktiv erreichbar.

Relevante Codepfade:

- `crates/vorce-ui/src/editors/module_canvas/inspector/hue.rs`
- `crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs`
- `crates/vorce-ui/src/editors/module_canvas/draw/add_node.rs`
- `crates/vorce-ui/src/editors/module_canvas/utils/catalog.rs`
- `crates/vorce/src/orchestration/evaluation.rs`
- `crates/vorce-core/src/module_eval/evaluator/mod.rs`

## Verifikation

Erfolgreich ausgefuehrt im aktuellen Workspace:

- `cargo fmt --all`
- `cargo check -p vorce-core --message-format short`
- `cargo check -p vorce-ui --message-format short`
- `cargo check -p vorce --message-format short`
- `cargo test -p vorce-core test_hue_node_uses_static_defaults_without_trigger_inputs -- --nocapture`
- `cargo test -p vorce-ui test_node_catalog_hides_unsupported_items -- --nocapture`
- `cargo test -p vorce test_release_smoke_automation_empty_project -- --nocapture`

Hinweis zum Smoke-Test:

- Der vorhandene App-Smoke-Test ist im Repo als `ignored, requires GPU and display` markiert. Die Testausfuehrung war deshalb korrekt `ignored`, nicht fehlgeschlagen.

## Konsequenz fuer `#61`

- `#61` kann fachlich erst dann sauber auf `Done`, wenn dieser lokale Stand remote integriert ist.
- Nach Push/Merge gibt es aus dem Codeaudit dieses Durchlaufs keine verbliebene technische Restarbeit mehr innerhalb der bearbeiteten MAI-004-Subissues.
