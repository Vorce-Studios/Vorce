## 2024-05-18 - [Rust/egui String Search Performance vs Unicode Case-Folding]
**Erkenntnis:** "Zero-allocation" ASCII-Hacks (wie `eq_ignore_ascii_case` auf Byte-Windows) für die Textsuche in Rendering-Loops zerschießen Unicode Case-Folding (z.B. Umlaute). Die `.to_lowercase()`-Allokation ist zwingend nötig für korrekte Suchergebnisse bei internationalen Zeichen.
**Aktion:** Verwende Lazy Evaluation und Early Returns (`if filter.is_empty() { return true; }`), um die teure String-Allokation in UI-Loops nur dann auszulösen, wenn der Nutzer *tatsächlich* eine Suchanfrage eingegeben hat. So bleiben Unicode-Suchfunktionen korrekt und im Normalfall (leeres Suchfeld) fällt kein Performance-Penalty an.

## 2024-05-24 - [Avoid Intermediate HashSets for Small Lookups]
**Erkenntnis:** In Rust loops, mapping an array of values into a `HashSet` to perform an `O(1)` `.contains()` check is an anti-pattern when the data set is small and the loop runs frequently (like in media orchestration ticks). The allocation overhead and hashing cost far outweigh a simple `O(N)` linear `.find()`.
**Aktion:** Avoid temporary `HashSet` allocations for small cross-referencing tasks in hot loops; rely on direct iterator methods instead. Also ensure ownership transfer is favored over `.clone()` when the source variable is no longer needed.

## 2025-03-25 - [Redundant String Allocation in Loops]
**Erkenntnis:** Found a common pattern in UI filtering where `String::to_lowercase()` was called inside a `.filter()` iterator closure. This causes O(N) heap allocations during search operations, degrading UI performance with large media libraries.
**Aktion:** Always pre-compute and cache string transformations like `to_lowercase()` in the corresponding models (e.g. `MediaItem`, `EffectPreset`, `MediaEntry`) instead of dynamically calling `to_lowercase()` inside `filter()` closures during UI searches. This significantly reduces allocations and speeds up query operations.

## 2025-04-05 - [Reusable HashSets in Hot Loops]
**Erkenntnis:** When a `HashSet` is required for `O(1)` lookups within a high-frequency loop (like `TriggerSystem::update`), allocating it per frame causes measurable overhead. However, replacing it with a `Vec` to avoid allocations introduces an `O(N)` lookup regression, which is a classic performance trap.
**Aktion:** To eliminate allocations without sacrificing `O(1)` lookup speed, hoist the `HashSet` into a persistent struct field and call `.clear()` at the start of the loop. This retains the allocated memory capacity across frames, combining the best of both worlds.
