# Lina StyleUI Journal

## 2026-04-10 - Visuelle Theme-Konsistenz in Media Browser Widgets
**Erkenntnis:** Im `MediaBrowser` wurden hartcodierte `Color32::from_rgb` Werte für die Hintergrundfarben der Thumbnails, Selektions-Zustände und Platzhalter-Icons verwendet. Solche hartcodierten Farben brechen die visuelle Konsistenz und Lesbarkeit beim Wechsel in verschiedene Theme-Varianten (z.B. Light Mode oder andere Dark Mode Varianten).
**Aktion:** Zukünftig immer prüfen, ob in UI-Komponenten (besonders Custom Widgets) die dynamischen egui-Theme-Variablen wie `ui.visuals().selection.bg_fill` oder `ui.visuals().text_color().gamma_multiply(...)` verwendet werden. `Color32::WHITE` als Bild-Tint-Farbe sollte beibehalten werden, um die originalen Bildfarben zu erhalten, aber Platzhalter-Icons sollten sich an die Textfarbe des Themes anpassen.

## 2026-05-18 - Replacing Hardcoded Colors with Theme Variables
**Erkenntnis:** Many UI components in `vorce-ui` (like `audio_meter.rs`, `custom.rs`, and `module_sidebar.rs`) use hardcoded colors such as `Color32::WHITE` for text. This breaks contrast when switching to light themes or different dark modes, as the text might become unreadable or lack visual harmony.
**Aktion:** Always use dynamic theme variables like `ui.visuals().text_color()` for text colors. This ensures consistency across all themes and avoids contrast issues when users change their theme. Avoid `Color32::WHITE` and other hardcoded colors whenever they are intended to render standard text or icons that should adapt to the theme.

## 2026-06-25 - Hartcodierte Farben in Timeline und Module Canvas
**Erkenntnis:** Weitere Komponenten (`timeline_v2/ui.rs`, `module_canvas/draw/part.rs`, `toast.rs` und `inspector/ui.rs`) verwendeten hartcodiertes `Color32::WHITE` für Text, Icons und interaktive Ring-Effekte.
**Aktion:** Diese wurden systematisch auf `ui.visuals().text_color()` und `ui.visuals().strong_text_color()` (für Hover-States) umgestellt. Die Multiplikation der Intensität (z. B. bei Hover-Ringen oder Toasts) bleibt erhalten, wendet sich jedoch nun korrekt auf die Theme-spezifische Basis-Farbe an.

## 2026-10-31 - Dynamische Hintergrundfarben in Grid und Minimap
**Erkenntnis:** Im `draw_grid` (Canvas & Mesh Editor) und `draw_mini_map` wurden hartcodierte Farbwerte (z.B. `Color32::from_rgb(40, 40, 40)`) für Hintergründe, Gitterlinien und Rahmen verwendet. Dies führt in anderen Dark- oder Light-Themes zu Kontrast- und Lesbarkeitsproblemen.
**Aktion:** Gitterlinien- und Hintergrundfarben in Canvas- und Editor-Komponenten sollten immer über Theme-Variablen wie `ui.visuals().panel_fill.gamma_multiply(0.9)`, `ui.visuals().window_stroke().color` oder abgedimmte Textfarben (`ui.visuals().text_color().gamma_multiply(0.1)`) realisiert werden, um sicheren Kontrast in jedem Theme zu garantieren.
