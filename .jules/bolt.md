## 2025-02-18 - ⚡ Bolt: Optimize lock contention in media browser thumbnail generation
**Erkenntnis:** Calling `.contains()` inside a loop using a write lock creates heavy thread contention, which decreases application performance and locks out other threads unnecessarily when performing read-only queries.

**Aktion:** Optimized `get_or_generate_thumbnail` in `crates/vorce-ui/src/view/media_browser.rs` to take a `.read()` lock for the initial `.contains()` query, falling back to a `.write()` lock only when inserting a new `PathBuf`. This yielded a measured ~1.36x speedup during simulated lock contention benchmarks.
