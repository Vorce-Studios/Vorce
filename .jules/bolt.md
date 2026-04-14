## 2024-04-14 - Reduzierung von String-Allokationen in UI Render-Loops
**Erkenntnis:** Die häufige Generierung und der Aufruf von `.to_lowercase()` für statische UI-Texte (wie die Socket-Namen) innerhalb von `egui` Render-Loops führt zu unzähligen, absolut unnötigen Heap-Allokationen, die die Performance (in Rust) belasten.
**Aktion:** Für statische Enum-Varianten eine explizite `name_lower()` Funktion implementieren, um String-Referenzen statt Heap-Strings zurückzugeben. Bei Such-Abgleichen immer zuerst einen Lazy Check machen, ob der Wert schon passt, bevor konvertiert wird.
