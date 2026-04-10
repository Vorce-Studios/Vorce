# Lina StyleUI Journal

## 2024-05-15 - Node Editor Colors
**Erkenntnis:** Hardcodierte Farben (wie Color32::from_rgb(40, 40, 40)) wurden im Node Editor (canvas backgrounds, sockets, grid) verwendet. Dies führte zu fehlerhaftem Kontrast und beeinträchtigter Lesbarkeit in hellen oder High-Contrast Themes. 
**Aktion:** Immer den &Ui-Kontext an tiefere Zeichen-Funktionen weiterleiten, um ui.visuals() abzufragen und dynamische Theme-Farben zu garantieren.

## 2024-04-10 - Visuelle Theme-Konsistenz in Media Browser Widgets
**Erkenntnis:** Im `MediaBrowser` wurden hartcodierte `Color32::from_rgb` Werte für die Hintergrundfarben der Thumbnails, Selektions-Zustände und Platzhalter-Icons verwendet. Solche hartcodierten Farben brechen die visuelle Konsistenz und Lesbarkeit beim Wechsel in verschiedene Theme-Varianten (z.B. Light Mode oder andere Dark Mode Varianten).
**Aktion:** Zukünftig immer prüfen, ob in UI-Komponenten (besonders Custom Widgets) die dynamischen egui-Theme-Variablen wie `ui.visuals().selection.bg_fill` oder `ui.visuals().text_color().gamma_multiply(...)` verwendet werden. `Color32::WHITE` als Bild-Tint-Farbe sollte beibehalten werden, um die originalen Bildfarben zu erhalten, aber Platzhalter-Icons sollten sich an die Textfarbe des Themes anpassen.

## 2024-04-10 - Visuelle Theme-Konsistenz in Media Browser Widgets
**Erkenntnis:** Im `MediaBrowser` wurden hartcodierte `Color32::from_rgb` Werte für die Hintergrundfarben der Thumbnails, Selektions-Zustände und Platzhalter-Icons verwendet. Solche hartcodierten Farben brechen die visuelle Konsistenz und Lesbarkeit beim Wechsel in verschiedene Theme-Varianten (z.B. Light Mode oder andere Dark Mode Varianten).
**Aktion:** Zukünftig immer prüfen, ob in UI-Komponenten (besonders Custom Widgets) die dynamischen egui-Theme-Variablen wie `ui.visuals().selection.bg_fill` oder `ui.visuals().text_color().gamma_multiply(...)` verwendet werden. `Color32::WHITE` als Bild-Tint-Farbe sollte beibehalten werden, um die originalen Bildfarben zu erhalten, aber Platzhalter-Icons sollten sich an die Textfarbe des Themes anpassen.
