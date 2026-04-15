## 2025-04-13 - [Optimiere String-Allokationen in UI Render-Loops]
**Erkenntnis:** Die Suche und Darstellung in UI Render-Loops (z.B. egui) ist anfällig für Redundanzen wie das häufige Konvertieren von Strings zu Lowercase innerhalb von Filtern, was pro Frame viele Allokationen auslöst.
**Aktion:** Berechne Lowercase-Versionen von Suchbegriffen einmal außerhalb der Iteration oder speichere Lowercase-Werte von Modellen (z.B. MediaEntry, NodeCatalogItem), um teure String-Operationen im Render-Loop zu vermeiden.
