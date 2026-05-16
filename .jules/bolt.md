## 2025-05-24 - DoS via Option::unwrap() in Media Library

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich in der `refresh()` Funktion der Media Library (`crates/vorce-ui/src/core/asset_manager.rs`), wenn auf den Pfad zugegriffen wurde.
**Lektion:** Direkte `unwrap()` Aufrufe auf Datei-Operationen oder Pfad-Optionen kÃ¶nnen bei fehlenden Berechtigungen oder gelÃ¶schten Dateien zum Absturz fÃ¼hren.
**Aktion:** Ersetzt durch sicheres Error Handling mit `Result` und Log-Ausgabe.

## 2025-05-15 - N+1 Syscalls in Media Library Refresh
**Erkenntnis:** The `MediaLibrary::refresh` loop was triggering N+1 disk I/O and excessive string allocations. Using `path.is_file()` issued an unnecessary `stat` syscall, while `path.to_string_lossy().to_string()` allocated multiple times in the hot loop even for pre-scanned files.
**Aktion:** Replaced `path.is_file()` with `entry.file_type().is_file()` (which leverages WalkDir's internal directory traversal cache) and short-circuited `|| self.items.contains_key(path)` to prevent string allocations via `into_owned()` and metadata syscalls for existing paths.

## 2025-05-07 - Zero-Allocation Case-Insensitive Search in Hot Paths
**Erkenntnis:** Using `.to_lowercase().contains(...)` inside iterators or UI render loops for searches allocates memory continuously every frame. While `socket.name` and `type_name` seem innocuous, their constant allocation creates hidden latency and pressure on the memory allocator.
**Aktion:** Replaced dynamic lowercase allocation with a custom `utils::case_insensitive_contains` function that does zero-allocation ASCII-aware comparisons using `.eq_ignore_ascii_case()` combined with a substring search window, significantly improving continuous render loop performance during active searches.

## 2025-02-12 - Zero-Allocation Case-Insensitive Search in Hot Paths (Search Popup)
**Erkenntnis:** Immediate-mode UIs wie egui rufen Render-Funktionen 60x pro Sekunde auf. Das Ausführen von `.to_lowercase()` innerhalb eines Iterators in der Such-Funktion `draw_search_popup` erzeugt jeden Frame unzählige überflüssige Heap-Allokationen (String-Instanziierungen).
**Aktion:** Der Ansatz wurde durch die Verwendung der bestehenden Methode `utils::case_insensitive_contains` ersetzt, welche den Vergleich ASCII-basiert ohne Speicherallokationen (zero-allocation) ausführt. Zustände, die für Vergleiche transformiert werden müssen, sollten ge-cached werden. Wenn dies nicht möglich ist, ist eine allocation-freie String-Vergleichsfunktion entscheidend.

## 2025-05-10 - Avoid Caching UI State for Public Fields (ModuleCanvas Search)
**Erkenntnis:** Caching lowercased search strings in `egui` state structs using `response.changed()` causes state desynchronization bugs when the source fields (like `search_filter` or `quick_create_filter`) are `pub` and can be modified programmatically elsewhere. This pattern attempts to avoid per-frame allocations but introduces subtle bugs.
**Aktion:** Instead of caching derived string state for `pub` fields, remove the cached state entirely. Use the zero-allocation `utils::case_insensitive_contains` inside the filter loops directly with the original string. This achieves both zero per-frame allocations and guaranteed state synchronization.

## 2024-05-15 - Asset Manager Loading Optimization
**Erkenntnis:** Synchronous directory reads during AssetManager initialization blocks the main thread.
**Aktion:** Moved file reading and JSON parsing for presets to a background thread using std::thread::spawn and crossbeam channels for non-blocking updates.
