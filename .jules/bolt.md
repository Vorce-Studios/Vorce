## 2025-02-12 - Prevent Per-Frame String Allocation in UI Hot Paths
**Erkenntnis:** Immediate-mode UIs wie egui rufen Render-Funktionen 60x pro Sekunde auf. Wenn man innerhalb einer Schleife in `draw_search_popup` und `draw_quick_create_popup` kontinuierlich `.to_lowercase()` auf dem Such-Filter ausführt, erzeugt dies massive, unnötige Heap-Allokationen (String-Instanziierungen). Dies belastet den Garbage Collector (bzw. führt in Rust zu unnötigem Speicherdruck) und verlangsamt den Render-Thread erheblich, vor allem bei langen Listen.
**Aktion:** Zustände, die für Vergleiche transformiert werden müssen (wie lowercased Strings), sollten im State-Struct ge-cached und NUR aktualisiert werden, wenn sich das Original ändert (`response.changed()`). Die Eigenschaft muss gekapselt oder das `changed()`-Signal der UI-Komponente genutzt werden.

## 2025-02-12 - Prevent Per-Frame String Allocation in UI Hot Paths (EffectChainPanel)
**Erkenntnis:** Immediate-mode UIs wie egui rufen Render-Funktionen 60x pro Sekunde auf. Das Ausführen von `.to_lowercase()` auf UI-State wie Suchfiltern *jeden Frame*, selbst wenn es außerhalb einer inneren Schleife passiert, erzeugt kontinuierlich unnötige Heap-Allokationen (String-Instanziierungen). Dies belastet den Memory Allocator und kann zu unerwarteten Stottern im Render-Thread führen.
**Aktion:** Zustände, die für Vergleiche transformiert werden müssen (wie lowercased Strings), sollten im State-Struct ge-cached und NUR aktualisiert werden, wenn sich das Original ändert (z.B. durch `response.changed()`).

## 2024-05-19 - N+1 Disk IO with WalkDir in hot path
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

<<<<<<< HEAD
## 2024-05-18 - [Vorce UI Shortcuts Panel - Prevent allocations in input event handler] **Erkenntnis:** Avoid calling `ui.input(|i| i.clone())` which clones the entire `egui::InputState` per frame during the shortcuts panel edit dialog. Instead, borrow it directly using `ui.input(|i| { ... })`. **Aktion:** Pass a closure that uses the borrowed input state to evaluate key bindings, avoiding unnecessary memory allocation.
=======
## 2025-02-24 - Avoid cloning InputState in egui
**Erkenntnis:** In immediate-mode GUIs (egui), when handling user input (like keyboard shortcuts), avoid cloning the entire `InputState` using `let input = ui.input(|i| i.clone());` on every frame. This creates unnecessary allocations in the hot loop, which can cause micro-stutters.
**Aktion:** Use the closure to directly borrow and evaluate the required state (e.g., `ui.input(|i| { /* process events inline */ })`) to perform all necessary checks without allocating new memory.

## 2025-01-01 - Avoid cloning entire Pointer state in egui **Erkenntnis:** In egui-Anwendungen kann das Klonen großer Zustandsstrukturen wie `ui.ctx().input(|i| i.pointer.clone())` pro Frame zu signifikanten unnötigen Allokationen führen. Dies ist besonders kritisch in Immediate Mode GUIs, wo dieser Code bis zu 60 Mal pro Sekunde ausgeführt wird. **Aktion:** Nutze Stattdessen Closures, um nur die spezifischen Boolean-Werte abzufragen, z.B. `ui.ctx().input(|i| (i.pointer.any_released(), i.pointer.any_click(), i.pointer.primary_down()))`.
>>>>>>> origin/main
