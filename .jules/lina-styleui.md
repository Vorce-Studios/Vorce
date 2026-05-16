# Lina StyleUI Journal

## 2026-04-10 - Visuelle Theme-Konsistenz in Media Browser Widgets
**Erkenntnis:** Im `MediaBrowser` wurden hartcodierte `Color32::from_rgb` Werte für die Hintergrundfarben der Thumbnails, Selektions-Zustände und Platzhalter-Icons verwendet. Solche hartcodierten Farben brechen die visuelle Konsistenz und Lesbarkeit beim Wechsel in verschiedene Theme-Varianten (z.B. Light Mode oder andere Dark Mode Varianten).
**Aktion:** Zukünftig immer prüfen, ob in UI-Komponenten (besonders Custom Widgets) die dynamischen egui-Theme-Variablen wie `ui.visuals().selection.bg_fill` oder `ui.visuals().text_color().gamma_multiply(...)` verwendet werden. `Color32::WHITE` als Bild-Tint-Farbe sollte beibehalten werden, um die originalen Bildfarben zu erhalten, aber Platzhalter-Icons sollten sich an die Textfarbe des Themes anpassen.

## 2026-05-18 - Replacing Hardcoded Colors with Theme Variables
**Erkenntnis:** Many UI components in `vorce-ui` (like `audio_meter.rs`, `custom.rs`, and `module_sidebar.rs`) use hardcoded colors such as `Color32::WHITE` for text. This breaks contrast when switching to light themes or different dark modes, as the text might become unreadable or lack visual harmony.
**Aktion:** Always use dynamic theme variables like `ui.visuals().text_color()` for text colors. This ensures consistency across all themes and avoids contrast issues when users change their theme. Avoid `Color32::WHITE` and other hardcoded colors whenever they are intended to render standard text or icons that should adapt to the theme.
