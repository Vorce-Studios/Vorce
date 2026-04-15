## 2025-02-12 - Prevent Heap Allocations in Search Filter Loop
**Erkenntnis:** Calling `.to_lowercase()` inside a high-frequency UI rendering loop (like in the preset search panel) generates unnecessary heap allocations on every frame when the search query is empty.
**Aktion:** I optimized `search_lower` assignment using lazy evaluation (`(!preset_search.is_empty()).then(|| preset_search.to_lowercase())`) so `.to_lowercase()` is never called when the search field is empty.
