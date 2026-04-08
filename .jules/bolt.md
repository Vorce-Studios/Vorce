## 2024-05-18 - [Rust/egui String Search Performance vs Unicode Case-Folding]
**Erkenntnis:** "Zero-allocation" ASCII-Hacks (wie `eq_ignore_ascii_case` auf Byte-Windows) für die Textsuche in Rendering-Loops zerschießen Unicode Case-Folding (z.B. Umlaute). Die `.to_lowercase()`-Allokation ist zwingend nötig für korrekte Suchergebnisse bei internationalen Zeichen.
**Aktion:** Verwende Lazy Evaluation und Early Returns (`if filter.is_empty() { return true; }`), um die teure String-Allokation in UI-Loops nur dann auszulösen, wenn der Nutzer *tatsächlich* eine Suchanfrage eingegeben hat. So bleiben Unicode-Suchfunktionen korrekt und im Normalfall (leeres Suchfeld) fällt kein Performance-Penalty an.
## 2024-05-18 - [Rust/egui String Search Performance vs Unicode Case-Folding]
**Erkenntnis:** "Zero-allocation" ASCII-Hacks (wie `eq_ignore_ascii_case` auf Byte-Windows) für die Textsuche in Rendering-Loops zerschießen Unicode Case-Folding (z.B. Umlaute). Die `.to_lowercase()`-Allokation ist zwingend nötig für korrekte Suchergebnisse bei internationalen Zeichen.
**Aktion:** Verwende Lazy Evaluation und Early Returns (`if filter.is_empty() { return true; }`), um die teure String-Allokation in UI-Loops nur dann auszulösen, wenn der Nutzer *tatsächlich* eine Suchanfrage eingegeben hat. So bleiben Unicode-Suchfunktionen korrekt und im Normalfall (leeres Suchfeld) fällt kein Performance-Penalty an.

<<<<<<< HEAD
## 2024-05-18 - [Rust/egui String Search Performance vs Unicode Case-Folding]
**Erkenntnis:** "Zero-allocation" ASCII-Hacks (wie `eq_ignore_ascii_case` auf Byte-Windows) für die Textsuche in Rendering-Loops zerschießen Unicode Case-Folding (z.B. Umlaute). Die `.to_lowercase()`-Allokation ist zwingend nötig für korrekte Suchergebnisse bei internationalen Zeichen.
**Aktion:** Verwende Lazy Evaluation und Early Returns (`if filter.is_empty() { return true; }`), um die teure String-Allokation in UI-Loops nur dann auszulösen, wenn der Nutzer *tatsächlich* eine Suchanfrage eingegeben hat. So bleiben Unicode-Suchfunktionen korrekt und im Normalfall (leeres Suchfeld) fällt kein Performance-Penalty an.
=======
## 2025-03-25 - [Redundant String Allocation in Loops]
**Learning:** Found a common pattern in UI filtering where `String::to_lowercase()` was called inside a `.filter()` iterator closure. This causes O(N) heap allocations during search operations, degrading UI performance with large media libraries.
**Action:** Always pre-compute and cache string transformations like `to_lowercase()` in the corresponding models (e.g. `MediaItem`, `EffectPreset`, `MediaEntry`) instead of dynamically calling `to_lowercase()` inside `filter()` closures during UI searches. This significantly reduces allocations and speeds up query operations.

## 2025-04-02 - [Zero-Allocation Substring Search in Loops vs Unicode Support]
**Erkenntnis:** Using byte-slice window comparisons (`.as_bytes().windows(len).any(|w| w.eq_ignore_ascii_case(...))`) to avoid O(N) string allocations during UI filtering breaks case-insensitive search for Unicode characters (like 'Ü'). This constitutes a functionality regression.
**Aktion:** While zero-allocation checks are important, functionality comes first. If full Unicode support is required (as in general UI search), pre-compute the lowercase variants outside the iterator instead of using byte-level ASCII checks. If we cannot pre-compute easily and Unicode support is needed, we must accept the string allocation or cache the lowercase representations within the structs.
>>>>>>> d3ed96942 (⚡ Bolt: UI Search String Allocation Optimization)
