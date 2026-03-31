# MAI-004 Foundation Status Reassessment

Stand: 2026-03-31

## Zweck

Dieses Dokument ersetzt die Closeout-Annahme vom 2026-03-30. Der Stand unten basiert auf einer fachlichen Gegenpruefung des aktuellen `main`-Codes sowie dem Live-Stand von GitHub-Issues, PRs und aktiven Jules-Sessions.

## Gesamtfazit

- `Vorce-Studios/Vorce#61` bleibt offen. Die Closeout-Aussage vom 2026-03-30 ist nach dem erneuten Codeaudit nicht haltbar.
- Alle bereits bearbeiteten Foundation-Subissues `#56`, `#57`, `#60`, `#62`, `#63`, `#64`, `#65`, `#66`, `#67` und `#68` stehen auf GitHub weiterhin auf `OPEN`.
- Ein gemergter PR allein reicht hier nicht als Abschlusskriterium. Mehrere Tickets haben bereits Code auf `main`, enthalten aber noch offene fachliche Luecken oder ungeklaerte Tracker-/Jules-Zustaende.

## Statusklassen

- `Teilweise umgesetzt`: sichtbare Fortschritte auf `main`, aber klare Restluecken gegen den Ticket-Scope.
- `Weitgehend im Code gelandet`: Hauptscope ist im aktiven Code sichtbar, aber End-to-End-Verifikation oder sauberer Closeout fehlt noch.
- `Aktive Folgearbeit`: offener PR oder laufende Jules-Arbeit blockiert einen Abschluss weiterhin.

## Status je Subissue

### `#56` Schema-Driven Inspector Completion

- Delivery-Stand: Issue `OPEN`, `PR #85` am 2026-03-30 gemerged.
- Fachlicher Befund:
  - `crates/vorce-core/src/module/types/schema.rs` liefert die zentrale Schema-Abfrage `has_trigger_mapping()`.
  - `crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs` nutzt diese Schema-Abfrage bereits fuer das Trigger-Mapping-Gating.
  - `crates/vorce-ui/src/editors/module_canvas/inspector/output.rs` zeigt Projector-Basisfelder wie `output_width`, `output_height` und `output_fps`.
  - Gleichzeitig existieren im aktiven Inspector weiter mehrere Sonderpfade mit expliziten Unsupported-/Placeholder-Warnungen, unter anderem in `inspector/common.rs`, `inspector/layer.rs`, `inspector/source.rs` und `inspector/output.rs`.
- Status: `Teilweise umgesetzt`. Das Ticket ist noch nicht closebar.

### `#57` Runtime Render Queue Feature Parity

- Delivery-Stand: Issue `OPEN`, `PR #92` seit 2026-03-30 geschlossen und nicht gemerged; aktuelle Jules-Session `17334415686066246325` steht auf `COMPLETED`, aber ohne verlinkten PR.
- Fachlicher Befund:
  - Die `RuntimeRenderQueue` existiert produktiv bereits.
  - `crates/vorce/src/orchestration/evaluation.rs` erzeugt aber weiterhin `blend_mode_unsupported`- und `masks_unsupported`-Diagnostik.
  - `crates/vorce/src/app/loops/render/content.rs` dokumentiert weiterhin, dass nur Edge Blending im sicheren Post-Processing unterstuetzt wird und Color Calibration bewusst ignoriert wird.
- Status: `Teilweise umgesetzt`. Der Render-Queue-Unterbau ist da, Feature-Paritaet im sichtbaren Renderpfad aber nicht.

### `#60` Node Fault Isolation and Diagnostics

- Delivery-Stand: Issue `OPEN`, `PR #88` am 2026-03-29 gemerged.
- Fachlicher Befund:
  - Strukturierte Diagnostics sind im aktiven Runtime-Pfad vorhanden.
  - `crates/vorce/src/orchestration/outputs.rs` propagiert Fehler bei `create_output_window(...)` weiterhin per `?` aus `sync_output_windows(...)` heraus.
  - Damit ist Fault Isolation fuer Output-/Window-Erzeugung nicht vollstaendig lokalisiert.
- Status: `Teilweise umgesetzt`. Solide Fortschritte vorhanden, aber Acceptance Criteria noch nicht voll getroffen.

### `#62` Trigger Event Nodes Migration

- Delivery-Stand: Issue `OPEN`, `PR #87` am 2026-03-30 gemerged.
- Fachlicher Befund:
  - `crates/vorce-ui/src/editors/module_canvas/inspector/trigger.rs` enthaelt differenzierte Inspector-Pfade fuer `Beat`, `Random`, `Fixed`, `Midi`, `Shortcut` und `AudioFFT`.
  - Die Event-spezifische UI und die Fixed-Timer-Cadence-Vorschau sind im aktiven Code sichtbar.
  - Das gemeinsame Trigger-Mapping-Gating laeuft ueber `part.schema().has_trigger_mapping()`.
- Status: `Weitgehend im Code gelandet`. Aus dem aktuellen Code ergibt sich kein grober Restblocker, aber das Ticket ist noch nicht formal verifiziert und geschlossen.

### `#63` Trigger Signal Nodes Migration

- Delivery-Stand: Issue `OPEN`, `PR #86` am 2026-03-30 gemerged.
- Fachlicher Befund:
  - `crates/vorce-ui/src/editors/module_canvas/inspector/trigger.rs` zeigt passende Live-/Preview-Pfade fuer `AudioFFT` und `Midi`.
  - `crates/vorce-core/src/module_eval/evaluator/triggers.rs` wertet `Midi`-Signale aktiv aus.
  - Derselbe Evaluator faellt bei `AudioFFT` ohne explizit aktivierte Outputs kontrolliert auf Beat-Output zurueck.
- Status: `Weitgehend im Code gelandet`. Das Ticket wirkt fachlich weit fortgeschritten, braucht aber noch saubere Abschlussverifikation.

### `#64` Media File Source Nodes Migration

- Delivery-Stand: Issue `OPEN`, `PR #89` am 2026-03-30 gemerged; die aktuelle Jules-Session `14540972759070123130` steht trotzdem noch auf `IN_PROGRESS` und verlinkt denselben PR.
- Fachlicher Befund:
  - `crates/vorce-ui/src/editors/module_canvas/inspector/source.rs` deckt `MediaFile`, `VideoUni`, `ImageUni`, `VideoMulti` und `ImageMulti` sichtbar ab.
  - `crates/vorce/src/orchestration/media.rs` und `crates/vorce-core/src/module_eval/evaluator/traversal.rs` enthalten passende Runtime-/Traversal-Pfade fuer dieselben Familien.
  - Ein offensichtlicher grober Familien-Drift ist im aktuellen Code nicht mehr sichtbar.
- Status: `Weitgehend im Code gelandet`. Die fachliche Restarbeit liegt vor allem in Verifikation und dem inkonsistenten Jules-/Tracker-Zustand.

### `#65` Layer and Projector Nodes Migration

- Delivery-Stand: Issue `OPEN`, Jules-Session `10541395446807407408` ist inzwischen `COMPLETED`, `PR #125` ist aber noch `OPEN`.
- Fachlicher Befund:
  - `crates/vorce-ui/src/editors/module_canvas/inspector/layer.rs` markiert `LayerType::Group` weiterhin als nur Single-aehnlich und `LayerType::All` weiterhin als nicht renderbar.
  - `crates/vorce-core/src/module_eval/evaluator/mod.rs` behandelt `LayerType::Group`, faellt fuer andere Layer-Typen aber weiter auf `continue` zurueck.
  - `crates/vorce/src/orchestration/outputs.rs` uebernimmt fuer Projector-Konfigurationen aktuell nur `id`, `name`, `output_width` und `output_height`; Felder wie `target_screen`, `hide_cursor`, `show_in_preview_panel` und `extra_preview_window` werden dort nicht aktiv synchronisiert.
- Status: `Teilweise umgesetzt` plus `Aktive Folgearbeit`. Das Ticket bleibt klar offen.

### `#66` Bevy Source Nodes Migration

- Delivery-Stand: Issue `OPEN`, `PR #95` am 2026-03-29 gemerged.
- Fachlicher Befund:
  - Der aktive Code enthaelt Bevy-Source-Unterbau.
  - `crates/vorce-ui/src/editors/module_canvas/inspector/source.rs` zeigt fuer `SourceType::Bevy3DModel` aber weiterhin nur `Model controls not yet implemented.`
- Status: `Teilweise umgesetzt`. Der Scope ist noch nicht vollstaendig im aktiven Inspector angekommen.

### `#67` External IO Nodes Gating and Migration

- Delivery-Stand: Issue `OPEN`, `PR #90` am 2026-03-30 gemerged.
- Fachlicher Befund:
  - `crates/vorce-ui/src/editors/module_canvas/inspector/capabilities.rs` markiert Shader, LiveInput, NDI und Spout weiterhin bewusst als nicht end-to-end unterstuetzt.
  - `crates/vorce-ui/src/editors/module_canvas/utils/catalog.rs` und `draw/add_node.rs` verwenden dieses Capability-Gating.
  - `crates/vorce/src/orchestration/evaluation.rs` loggt diese Familien zur Laufzeit explizit als unsupported/experimental.
- Status: `Weitgehend im Code gelandet`. Fuer den Gating-Anteil ist der Code konsistent; ein formaler Closeout fehlt aber noch.

### `#68` Hue Node Model Runtime Gating and Spatial Editor

- Delivery-Stand: Issue `OPEN`, Jules-Session `8797109164578060998` ist `COMPLETED`, `PR #124` ist aber noch `OPEN`.
- Fachlicher Befund:
  - `crates/vorce-core/src/module_eval/evaluator/mod.rs` erzeugt bereits `SourceCommand::HueOutput`.
  - `crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs` zeigt fuer Hue aktuell nur einen generischen Placeholder-Block ohne echte Family-spezifische Inspector-Steuerung.
  - Im aktuellen `main` ist die Hue-Familie damit noch nicht sauber end-to-end abgeschlossen.
- Status: `Teilweise umgesetzt` plus `Aktive Folgearbeit`. Das Ticket ist nicht closebar, solange `PR #124` offen ist und der Main-Branch die Restarbeit noch nicht enthaelt.

## Konsequenz fuer `#61`

- `#61` darf weiterhin nicht als fachlich abgeschlossen beschrieben werden.
- Die Acceptance Criteria muessen auf den realen offenen Downstream-Stand zurueckgesetzt werden.
- Die Doku fuer MAI-004 muss einen Statustracker fuehren, keinen Closeout-Claim.

## Verifikation

Die Gegenpruefung fuer dieses Reassessment basiert auf dem aktiven Workspace und dem Live-Stand vom 2026-03-31:

- GitHub-Issues: `#56`, `#57`, `#60`, `#62`, `#63`, `#64`, `#65`, `#66`, `#67`, `#68`, `#61`
- Pull Requests: `#85`, `#86`, `#87`, `#88`, `#89`, `#90`, `#92`, `#95`, `#124`, `#125`
- Jules-Sessions: `17334415686066246325`, `14540972759070123130`, `10541395446807407408`, `8797109164578060998`
- Codepfade:
  - `crates/vorce-core/src/module/types/schema.rs`
  - `crates/vorce-core/src/module_eval/evaluator/mod.rs`
  - `crates/vorce-core/src/module_eval/evaluator/traversal.rs`
  - `crates/vorce-core/src/module_eval/evaluator/triggers.rs`
  - `crates/vorce/src/orchestration/evaluation.rs`
  - `crates/vorce/src/orchestration/media.rs`
  - `crates/vorce/src/orchestration/outputs.rs`
  - `crates/vorce/src/app/loops/render/content.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/common.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/layer.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/output.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/source.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/trigger.rs`
  - `crates/vorce-ui/src/editors/module_canvas/inspector/capabilities.rs`
  - `crates/vorce-ui/src/editors/module_canvas/utils/catalog.rs`
