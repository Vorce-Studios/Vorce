# MAI-004 Foundation Closeout

Stand: 2026-03-30

## Zweck

Dieses Dokument haelt fest, warum `Vorce-Studios/Vorce#61` auf Foundation-Ebene abgeschlossen werden kann, obwohl mehrere Downstream-Issues zur Node-Migration weiterhin offen sind.

## Abschlussentscheidung

- Die reine Foundation-Arbeit fuer die Node-System-Migration ist abgeschlossen.
- Die offenen Issues `#56`, `#57`, `#60`, `#62`, `#63`, `#64`, `#65`, `#66`, `#67` und `#68` sind verbleibende Familien-, Runtime-, Inspector- oder Verifikationsarbeit.
- Diese Folgearbeit bleibt wichtig, gehoert aber nicht mehr zur Greenfield-Grundlage von `#61`.

## Nachgewiesene Foundation-Bausteine

### 1. Socket- und Schema-Basis ist zentralisiert

- `crates/vorce-core/src/module/types/socket.rs` fuehrt stabile Socket-Metadaten wie `id`, `direction`, `supports_trigger_mapping`, `is_primary` und `accepts_multiple_connections`.
- `crates/vorce-core/src/module/types/schema.rs` liefert ueber `ModulePart::schema()` eine konsolidierte Schemaquelle fuer Node-Kind, Inputs, Outputs und Inspector-Mapping.

### 2. Graph-Validierung und Self-Heal sind produktiv

- `crates/vorce-core/src/module/types/module.rs` validiert Verbindungen ueber `validate_connection(...)` fachlich gegen die aktuelle Socket-Definition.
- `connect_parts(...)` ersetzt bei Bedarf unzulaessige Einzel-Input-Verbindungen deterministisch.
- `repair_graph()` normalisiert duplizierte oder leere Output-/Layer-IDs, entfernt ungueltige Trigger-Mappings und repariert kaputte oder doppelte Verbindungen.

### 3. Die Runtime arbeitet mit einer expliziten Render Queue

- `crates/vorce/src/app/core/app_struct.rs` definiert `RuntimeRenderQueueItem`, strukturierte `RenderDiagnostic`s und die konsolidierte `RuntimeRenderQueue`.
- `crates/vorce/src/orchestration/evaluation.rs` baut diese Queue pro Frame aus den Evaluator-Ergebnissen auf und haengt degradierte Runtime-Diagnostik an betroffene Eintraege an.

### 4. Output-/Window-Reconciliation ist nicht mehr nur Altlast

- `crates/vorce/src/orchestration/outputs.rs` fuehrt Projector-Nodes in den `OutputManager` ueber.
- Dasselbe Modul entfernt stale Output-Fenster deterministisch und loggt den Cleanup.

### 5. Sichtbarkeit und Inspector-Gating laufen ueber einen gemeinsamen Capability-Pfad

- `crates/vorce-ui/src/editors/module_canvas/utils/catalog.rs` baut den Node-Katalog capabilities-basiert auf, statt alle experimentellen Nodes blind sichtbar zu lassen.
- `crates/vorce-ui/src/editors/module_canvas/inspector/capabilities.rs` und die daran angeschlossenen Inspector-Dateien verwenden denselben Gating-Pfad fuer sichtbare Warnungen und deaktivierte Controls.

## Scope-Handoff nach dem Foundation-Abschluss

Die restliche Arbeit bleibt offen, ist aber nach dem aktuellen Zuschnitt fachlich sauber getrennt:

- `#56`: schema-/capability-getriebene Inspector-Paritaet
- `#57`: Runtime-Render-Queue-Feature-Paritaet
- `#60`: Fault Isolation und Diagnostics-Haertung
- `#62` und `#63`: Trigger-Familien
- `#64` und `#65`: Media-/Layer-/Projector-Familien
- `#66`, `#67` und `#68`: Spezial- und Device-Nodes
- `#58` und `#59`: Umbrella-/Pack-Koordination fuer die offenen Familien

## Verifikation

Die folgenden Verifikationen wurden am 2026-03-30 lokal gegen den aktuellen Workspace ausgefuehrt:

- `cargo check -p vorce-core --quiet`
- `cargo test -p vorce-core socket_tests --quiet`
- `cargo test -p vorce-ui test_node_catalog_hides_unsupported_items --quiet`
- `cargo check -p vorce --quiet`

Ergebnis:

- `vorce-core` baut.
- Die Socket-Schema-Tests laufen gruen.
- Der capability-basierte Node-Katalog-Test in `vorce-ui` laeuft gruen.
- Die `vorce`-App baut mit der aktiven Runtime-Queue-/Output-Orchestrierungsbasis.
