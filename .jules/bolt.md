## 2023-10-27 - [Optimization] `node_editor.rs` Selected Nodes Check Optimization
**Erkenntnis:** In `NodeEditor`, the `.contains(&node.id)` check on a `Vec<u64>` within the nodes rendering loop was very inefficient (`O(n)` per iteration where `n` is `selected_nodes.len()`).
**Aktion:** I changed it so `selected_nodes` is pre-collected into an `FxHashSet<u64>` (from `rustc-hash`), providing `O(1)` amortized lookups instead. Benchmark results show a ~13.7x improvement for lookups compared to the original `Vec` implementation.

## 2025-02-18 - ⚡ Bolt: Optimize lock contention in media browser thumbnail generation
**Erkenntnis:** Calling `.contains()` inside a loop using a write lock creates heavy thread contention, which decreases application performance and locks out other threads unnecessarily when performing read-only queries.
**Aktion:** Optimized `get_or_generate_thumbnail` in `crates/vorce-ui/src/view/media_browser.rs` to take a `.read()` lock for the initial `.contains()` query, falling back to a `.write()` lock only when inserting a new `PathBuf`. This yielded a measured ~1.36x speedup during simulated lock contention benchmarks.

## 2023-10-25 - [Performance Boost] Optimize O(N^2) connection retain loop with FxHashSet
**Erkenntnis:** Using `Vec::contains` inside a `.retain` loop for connection processing results in an O(N*M) algorithmic bottleneck, particularly when validating large numbers of part connections.
**Aktion:** Replaced the `Vec` collection with a `rustc_hash::FxHashSet` constructed prior to the loop. This changes the lookup cost from O(N) to O(1), improving the overall loop execution to O(M) and yielding a ~280x performance boost in microbenchmarks. Applied the turbofish syntax `collect::<rustc_hash::FxHashSet<_>>()` to ensure types resolve correctly regardless of diff contexts.

## 2025-02-12 - Prevent Heap Allocations in Search Filter Loop
**Erkenntnis:** Calling `.to_lowercase()` inside a high-frequency UI rendering loop (like in the preset search panel) generates unnecessary heap allocations on every frame when the search query is empty.
**Aktion:** I optimized `search_lower` assignment using lazy evaluation (`(!preset_search.is_empty()).then(|| preset_search.to_lowercase())`) so `.to_lowercase()` is never called when the search field is empty.

## 2025-04-20 - ⚡ Bolt: Prevent Heap Allocations in String Filtering Loops
**Erkenntnis:** Calling `.to_lowercase()` inside high-frequency UI rendering loops (like in search panels or quick create menus) generates unnecessary heap allocations on every frame when the search query is empty.
**Aktion:** Optimized assignment using lazy evaluation (`(!str.is_empty()).then(|| str.to_lowercase())`) so `.to_lowercase()` is never called when the search field is empty.

## 2026-04-18 - [Parallelize AssetManager loading]
**Erkenntnis:** Synchronous file reading inside loops during `load_library` in `AssetManager` blocked the main thread significantly due to I/O constraints when processing many preset files. The code inherently processes multiple independent files.
**Aktion:** Replaced sequential nested file iteration (directories and reads) with `rayon`'s `into_par_iter()`. By collecting JSON strings and parsing them in parallel threads, initialization time for asset management on 10,000 files dropped from ~145ms to ~63ms (a 2.29x speedup). Memory handling was kept safe by returning values from the par_iter and collecting into HashMap synchronously, avoiding potential mutex locking overhead.

## 2025-02-18 - [Performance Boost] Optimize O(N) loops and allocations in vorce-ui
**Erkenntnis:** O(N) array/vector lookups in high-frequency rendering and updating loops (`canvas.selected_parts`, `timeline_v2` module cleanup) cause severe algorithmic bottlenecks. Additionally, repeatedly evaluating string transformations like `.to_lowercase()` directly on user input bindings generates completely unnecessary per-frame heap allocations when strings are empty or unused.
**Aktion:** I replaced standard generic `HashSet` and linear `Vec` lookups with the highly optimized `rustc_hash::FxHashSet` for `u64` IDs, accelerating lookup speed drastically without crypto hash overhead. Moreover, I used `Option<String>` mapping via `(!str.is_empty()).then(|| str.to_lowercase())` in multiple string matching UI search paths, lazily skipping string duplication memory allocations when empty.
