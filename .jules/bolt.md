
## 2024-04-14 - Optimize SlotManager::assign_to_slot
**Erkenntnis:** The `assign_to_slot` function in `SlotManager` iterated over all slot vectors and performed an O(N) mutation using `.retain(|&p| p != panel)`. Although N is typically small, repeatedly invoking closure operations across multiple vectors introduces overhead. Also, `!panels.contains(&panel)` internally repeats linear scans on the target array.
**Aktion:** Converted the targeted panel into a `HashSet` before the array iterations to significantly improve algorithmic efficiency and leverage set lookups inside closures. This reduced baseline latency from ~264ns to ~200ns in synthetic microbenchmarks.
