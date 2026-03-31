# Lina StyleUI Journal
## 2025-03-31 - Fix hardcoded colors in Timeline
**Erkenntnis:** Hardcoded colors like `Color32::from_rgb(40, 40, 40)` and `Color32::WHITE` were causing visual inconsistencies and poor contrast across different themes (especially in dark mode variants) in the Timeline panel.
**Aktion:** Always use dynamic egui theme properties via `ui.visuals()` (e.g., `extreme_bg_color`, `faint_bg_color`, `text_color()`, `strong_text_color()`, `selection.bg_fill`, `warn_fg_color`, `error_fg_color`) instead of hardcoded `Color32` values to ensure clear visual hierarchy and contrast in any selected theme.
