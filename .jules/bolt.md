## 2025-02-12 - Prevent Per-Frame String Allocation in UI Hot Paths
**Erkenntnis:** Immediate-mode UIs wie egui rufen Render-Funktionen 60x pro Sekunde auf. Wenn man innerhalb einer Schleife in `draw_search_popup` und `draw_quick_create_popup` kontinuierlich `.to_lowercase()` auf dem Such-Filter ausführt, erzeugt dies massive, unnötige Heap-Allokationen (String-Instanziierungen). Dies belastet den Garbage Collector (bzw. führt in Rust zu unnötigem Speicherdruck) und verlangsamt den Render-Thread erheblich, vor allem bei langen Listen.
**Aktion:** Zustände, die für Vergleiche transformiert werden müssen (wie lowercased Strings), sollten im State-Struct ge-cached und NUR aktualisiert werden, wenn sich das Original ändert (`response.changed()`). Die Eigenschaft muss gekapselt oder das `changed()`-Signal der UI-Komponente genutzt werden.

## 2025-02-12 - Prevent Per-Frame String Allocation in UI Hot Paths (EffectChainPanel)
**Erkenntnis:** Immediate-mode UIs wie egui rufen Render-Funktionen 60x pro Sekunde auf. Das Ausführen von `.to_lowercase()` auf UI-State wie Suchfiltern *jeden Frame*, selbst wenn es außerhalb einer inneren Schleife passiert, erzeugt kontinuierlich unnötige Heap-Allokationen (String-Instanziierungen). Dies belastet den Memory Allocator und kann zu unerwarteten Stottern im Render-Thread führen.
**Aktion:** Zustände, die für Vergleiche transformiert werden müssen (wie lowercased Strings), sollten im State-Struct ge-cached und NUR aktualisiert werden, wenn sich das Original ändert (z.B. durch `response.changed()`).

## 2024-05-19 - N+1 Disk IO with WalkDir in hot path
**Erkenntnis:** The `MediaLibrary::refresh` loop was triggering N+1 disk I/O and excessive string allocations. Using `path.is_file()` issued an unnecessary `stat` syscall, while `path.to_string_lossy().to_string()` allocated multiple times in the hot loop even for pre-scanned files.
**Aktion:** Replaced `path.is_file()` with `entry.file_type().is_file()` (which leverages WalkDir's internal directory traversal cache) and short-circuited `|| self.items.contains_key(path)` to prevent string allocations via `into_owned()` and metadata syscalls for existing paths.

## 2024-05-15 - Asset Manager Loading Optimization **Erkenntnis:** Synchronous directory reads during AssetManager initialization blocks the main thread. **Aktion:** Moved file reading and JSON parsing for presets to a background thread using std::thread::spawn.
