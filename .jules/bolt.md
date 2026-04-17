## 2024-05-24 - [Avoid Intermediate HashSets for Small Lookups]
**Learning:** In Rust loops, mapping an array of values into a `HashSet` to perform an `O(1)` `.contains()` check is an anti-pattern when the data set is small and the loop runs frequently (like in media orchestration ticks). The allocation overhead and hashing cost far outweigh a simple `O(N)` linear `.find()`.
**Action:** Avoid temporary `HashSet` allocations for small cross-referencing tasks in hot loops; rely on direct iterator methods instead. Also ensure ownership transfer is favored over `.clone()` when the source variable is no longer needed.

## 2025-03-25 - [Redundant String Allocation in Loops]
**Learning:** Found a common pattern in UI filtering where `String::to_lowercase()` was called inside a `.filter()` iterator closure. This causes O(N) heap allocations during search operations, degrading UI performance with large media libraries.
**Action:** Always pre-compute and cache string transformations like `to_lowercase()` in the corresponding models (e.g. `MediaItem`, `EffectPreset`, `MediaEntry`) instead of dynamically calling `to_lowercase()` inside `filter()` closures during UI searches. This significantly reduces allocations and speeds up query operations.

## 2025-03-25 - [Unicode Safety in Text Search Optimizations]
**Learning:** Using ASCII-only zero-allocation hacks (like `eq_ignore_ascii_case` on byte windows) for text search to avoid string allocations breaks Unicode case-folding (e.g., German Umlaute like 'ä', 'ö', 'ü'). Simply replacing it with lazy dynamic `.to_lowercase()` calls re-introduces the performance anti-pattern.
**Action:** Do not use `eq_ignore_ascii_case` on byte arrays for text search. Instead, use an allocation-free Unicode-aware string iterator like `crate::core::text::contains_ignore_case` which handles Unicode characters natively via `char_indices` without allocating new strings, preserving full Unicode support while safely improving performance in hot loops.
