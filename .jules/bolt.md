## 2026-03-21 - [Performance] Optimize valid_ids lookup in init.rs
**Erkenntnis:** The `valid_ids` collection in `run_self_heal` inside `crates/vorce/src/app/core/init.rs` was being built as a `Vec<u64>` and then queried inside a nested loop with `.contains(id)`, causing O(n) lookups.
**Aktion:** Replaced `Vec<u64>` with `rustc_hash::FxHashSet<u64>` to make the `valid_ids.contains(id)` lookup O(1), significantly reducing the loop iteration overhead.
