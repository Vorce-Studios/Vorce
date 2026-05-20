# Bolt - Knowledge Base & Lessons Learned

## 2024-11-20 - Use f64 for time calculation in Media
**Erkenntnis:** Using f32 for time calculation in media pipeline leads to precision issues and jitter over long durations.
**Aktion:** Use f64 for all time-related fields and calculations in `vorce-media`.

## 2024-12-05 - Modularize UI Widgets
**Erkenntnis:** A single large `custom.rs` for all UI widgets becomes unmaintainable.
**Aktion:** Moved custom widgets to `crates/vorce-ui/src/widgets/custom/` with dedicated modules for `buttons`, `sliders`, `layout`, etc.

## 2025-05-10 - Avoid Caching UI State for Public Fields (ModuleCanvas Search)
**Erkenntnis:** Caching lowercased search strings in `egui` state structs using `response.changed()` causes state desynchronization bugs when the source fields (like `search_filter` or `quick_create_filter`) are `pub` and can be modified programmatically elsewhere. This pattern attempts to avoid per-frame allocations but introduces subtle bugs.
**Aktion:** Instead of caching derived string state for `pub` fields, remove the cached state entirely. Use the zero-allocation `utils::case_insensitive_contains` inside the filter loops directly with the original string. This achieves both zero per-frame allocations and guaranteed state synchronization.

## 2025-05-18 - Avoid Per-Frame String Allocation in UI Hot Paths (MediaManagerUI)
**Erkenntnis:** Immediate-mode UIs wie egui rufen Render-Funktionen 60x pro Sekunde auf. Das Ausführen von `.to_lowercase()` innerhalb eines Render-Loops (hier `render_main_content` in `MediaManagerUI`) erzeugt jeden Frame unnötige Heap-Allokationen, die den Garbage Collector/Allocator belasten.
**Aktion:** Ersetzt durch das Caching des lowercased Such-Strings (`search_query_lower`), der nur bei Änderungen (`response.changed()`) aktualisiert wird. Im Render-Loop wird dann `str::contains()` auf den ebenso ge-cachten `item.name_lower` angewendet. Zusätzlich wird der ge-cachte String als `Arc<str>` gespeichert. Beim Iterieren über die MediaItems im Render-Loop wird nur das `Arc` geclont (cheap ref-bump), womit eine echte Zero-Allocation pro Frame (während einer aktiven Suche) erreicht wird, und es kann weiterhin die schnelle byte-level Suche von `str::contains` genutzt werden.
