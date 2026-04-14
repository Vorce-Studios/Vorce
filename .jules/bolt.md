## 2024-05-18 - FxHashSet für ID Lookups
**Erkenntnis:** Das Entfernen von "Dangling Connections" nutzte ein `std::collections::HashSet<u64>`. Der Standard-SipHash von Rust ist zwar kryptografisch sicher, aber für interne `u64` IDs unnötig langsam.
**Aktion:** Ersetzen des Standard-HashSets durch `rustc_hash::FxHashSet<u64>`, was in Benchmarks zu einer Reduzierung der Ausführungszeit um den Faktor 4 führte (z.B. 154ms -> 37ms bei 5000 Connections).
