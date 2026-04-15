<<<<<<< HEAD
## 2024-04-14 - Reduzierung von String-Allokationen in UI Render-Loops
**Erkenntnis:** Die häufige Generierung und der Aufruf von `.to_lowercase()` für statische UI-Texte (wie die Socket-Namen) innerhalb von `egui` Render-Loops führt zu unzähligen, absolut unnötigen Heap-Allokationen, die die Performance (in Rust) belasten.
**Aktion:** Für statische Enum-Varianten eine explizite `name_lower()` Funktion implementieren, um String-Referenzen statt Heap-Strings zurückzugeben. Bei Such-Abgleichen immer zuerst einen Lazy Check machen, ob der Wert schon passt, bevor konvertiert wird.
=======
## 2023-10-25 - [Performance Boost] Optimize O(N^2) connection retain loop with FxHashSet
**Erkenntnis:** Using `Vec::contains` inside a `.retain` loop for connection processing results in an O(N*M) algorithmic bottleneck, particularly when validating large numbers of part connections.
**Aktion:** Replaced the `Vec` collection with a `rustc_hash::FxHashSet` constructed prior to the loop. This changes the lookup cost from O(N) to O(1), improving the overall loop execution to O(M) and yielding a ~280x performance boost in microbenchmarks. Applied the turbofish syntax `collect::<rustc_hash::FxHashSet<_>>()` to ensure types resolve correctly regardless of diff contexts.
>>>>>>> main
