## 2023-10-25 - [Performance Boost] Optimize O(N^2) connection retain loop with FxHashSet
**Erkenntnis:** Using `Vec::contains` inside a `.retain` loop for connection processing results in an O(N*M) algorithmic bottleneck, particularly when validating large numbers of part connections.
**Aktion:** Replaced the `Vec` collection with a `rustc_hash::FxHashSet` constructed prior to the loop. This changes the lookup cost from O(N) to O(1), improving the overall loop execution to O(M) and yielding a ~280x performance boost in microbenchmarks. Applied the turbofish syntax `collect::<rustc_hash::FxHashSet<_>>()` to ensure types resolve correctly regardless of diff contexts.

## 2024-04-15 - [Performance Boost] Replace HashSet lookups with flat Vec map in egui render loop
**Erkenntnis:** Using `HashSet::contains` with small integer keys inside a hot UI loop causes measurable overhead due to the default SipHash execution. While O(1) in theory, the constant hash computation time becomes a bottleneck when called iteratively per frame.
**Aktion:** Pre-compute a flat `Vec<bool>` map before the loop. This changes the lookups inside the hot path from hashed access to direct O(1) array memory access, completely bypassing the hasher overhead while keeping algorithmic complexity linear.
