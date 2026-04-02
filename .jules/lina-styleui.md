# Lina StyleUI Journal
## 2024-05-24 - Visuelle Ruhe für Toolbar-Metriken
**Erkenntnis:** Hardcodierte Warn- und Error-Farben (z. B. grelles Grün für 'OK') erzeugen zu viel visuelles 'Rauschen', wenn eigentlich alles in Ordnung ist. Zudem kollidieren hartcodierte Farben (wie Color32::YELLOW oder Color32::from_rgb) in den Metriken mit verschiedenen Theme-Varianten.
**Aktion:** Nutze für den 'OK'-Zustand immer neutrale Farben (z. B. `ui.visuals().text_color().gamma_multiply(0.8)`), damit Fehler visuell stärker hervortreten. Verwende für Warnungen und Fehler immer `ui.visuals().warn_fg_color` bzw. `ui.visuals().error_fg_color`, um 100% Theme-Kohärenz zu gewährleisten.

## 2025-03-31 - Fix hardcoded colors in Timeline

**Erkenntnis:** Hardcoded colors like `Color32::from_rgb(40, 40, 40)` and `Color32::WHITE` were causing visual inconsistencies and poor contrast across different themes (especially in dark mode variants) in the Timeline panel.

**Aktion:** Always use dynamic egui theme properties via `ui.visuals()` (e.g., `extreme_bg_color`, `faint_bg_color`, `text_color()`, `strong_text_color()`, `selection.bg_fill`, `warn_fg_color`, `error_fg_color`) instead of hardcoded `Color32` values to ensure clear visual hierarchy and contrast in any selected theme.
