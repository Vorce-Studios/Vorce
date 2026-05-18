## ⚡ Performance Boost

**💡 Was:** Vermeidung von dynamischen String-Allokationen in der Suchfunktion des Module Canvas (`draw_search_popup`). `.to_lowercase()` wurde durch eine Zero-Allocation-Methode ersetzt.
**🎯 Warum:** Immediate-Mode-UIs rendern 60x pro Sekunde. Die Funktion `get_part_property_text` generiert dynamische Strings, auf denen jeden Frame `.to_lowercase()` aufgerufen wurde. Dies erzeugt eine kontinuierliche Belastung des Heaps und des Garbage Collectors / Memory Allocators.
**📊 Impact:** Eliminiert N String-Allokationen pro Frame während die Suchleiste im Module Canvas geöffnet ist (N = Anzahl der durchsuchten Elemente). Reduziert Micro-Stuttering.
**🔬 Messung:** Code Review. Die Such-Schleife verwendet nun Referenzen und das Allokations-freie `case_insensitive_contains`.

### Details:
- [x] Code wurde optimiert
- [x] Lesbarkeit bleibt erhalten
- [x] Tests laufen erfolgreich

## Verlinktes Issue
Fixes #1235
