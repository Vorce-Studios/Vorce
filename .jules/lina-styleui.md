# Lina StyleUI Journal

## 2026-04-10 - Visuelle Theme-Konsistenz in Media Browser Widgets
**Erkenntnis:** Im `MediaBrowser` wurden hartcodierte `Color32::from_rgb` Werte für die Hintergrundfarben der Thumbnails, Selektions-Zustände und Platzhalter-Icons verwendet. Solche hartcodierten Farben brechen die visuelle Konsistenz und Lesbarkeit beim Wechsel in verschiedene Theme-Varianten (z.B. Light Mode oder andere Dark Mode Varianten).
**Aktion:** Zukünftig immer prüfen, ob in UI-Komponenten (besonders Custom Widgets) die dynamischen egui-Theme-Variablen wie `ui.visuals().selection.bg_fill` oder `ui.visuals().text_color().gamma_multiply(...)` verwendet werden. `Color32::WHITE` als Bild-Tint-Farbe sollte beibehalten werden, um die originalen Bildfarben zu erhalten, aber Platzhalter-Icons sollten sich an die Textfarbe des Themes anpassen.

## 2026-05-18 - Replacing Hardcoded Colors with Theme Variables
**Erkenntnis:** Many UI components in `vorce-ui` (like `audio_meter.rs`, `custom.rs`, and `module_sidebar.rs`) use hardcoded colors such as `Color32::WHITE` for text. This breaks contrast when switching to light themes or different dark modes, as the text might become unreadable or lack visual harmony.
**Aktion:** Always use dynamic theme variables like `ui.visuals().text_color()` for text colors. This ensures consistency across all themes and avoids contrast issues when users change their theme. Avoid `Color32::WHITE` and other hardcoded colors whenever they are intended to render standard text or icons that should adapt to the theme.

## 2026-04-30 - Hardcoded Colors in Module Canvas Node Parts
**Erkenntnis:** The `vorce-ui` component `part.rs` inside the module canvas editor contained several instances of hardcoded colors (`Color32::WHITE`, `Color32::from_white_alpha(160)`, `Color32::from_gray(180)`, `Color32::from_gray(230)`) for drawing text galleys and labels, breaking visual consistency across themes.
**Aktion:** Replaced hardcoded text colors with dynamic theme variables like `ui.visuals().text_color()` and utilized `gamma_multiply()` to achieve the desired opacity/dimming effect while ensuring contrast and readability in any theme.
## 2026-05-01 - Media Manager UI Colors **Erkenntnis:** Hardcoded colors in media manager grid break contrast across different themes. **Aktion:** Replace hardcoded Color32 with ui.visuals() theme properties.

## 2026-06-01 - Floating Overlay Theme Colors
**Erkenntnis:** Hardcoded backgrounds and strokes in module canvas floating overlays (minimap, search, presets) break visual consistency in various theme variants.
**Aktion:** Use dynamic theme properties like ui.visuals().window_fill() and ui.visuals().widgets.noninteractive.bg_stroke.color instead of static Color32 values.
## 2026-05-05 - [Hue Spatial Editor Colors] **Erkenntnis:** Hardcoded colors in hue_spatial_editor break theme consistency and readability in different modes. **Aktion:** Always use ui.visuals() equivalents instead of Color32 constants in egui render loops.
## 2026-05-06 - Module Canvas Visual Consistency **Erkenntnis:** Hardcoded Color32 colors were used throughout the module canvas causing visual inconsistencies in different themes. **Aktion:** Replaced hardcoded Color32 colors with dynamic theme colors from ui.visuals() or crate::theme::colors.
## 2026-05-07 - Toolbar Metric Colors **Erkenntnis:** Hardcoded colors in the toolbar metrics break visual consistency across different themes. **Aktion:** Replace hardcoded Color32 with ui.visuals() theme properties.
## 2026-05-19 - Vorce UI Theme Colors Compliance
**Erkenntnis:** Several components (`icon_demo_panel.rs`, `cue_panel.rs`, `controller_overlay_panel`, `preview_panel.rs`) still used hardcoded `Color32` equivalents instead of dynamic `ui.visuals()` or `crate::theme::colors` references, which broke appearance across different active themes.
**Aktion:** Replaced hardcoded constants like `Color32::YELLOW`, `Color32::GREEN`, `Color32::RED`, `Color32::GRAY` with `ui.visuals().warn_fg_color`, `crate::theme::colors::MINT_ACCENT`, `ui.visuals().error_fg_color`, and `ui.style().visuals.text_color().gamma_multiply(0.6)` respectively. Ensuring dynamic rendering fixes UI contrast problems instantly.
## 2026-05-20 - Media Browser and Mesh Editor Theme Consistency
**Erkenntnis:** Hardcoded `Color32` values in the `media_browser` and `mesh_editor` components were causing visual inconsistencies and contrast issues when switching between different theme variants (e.g., from dark to light mode or between custom dark themes).
**Aktion:** Replaced hardcoded `Color32::from_rgb` and `Color32::WHITE` constants with dynamic `ui.visuals()` properties such as `selection.bg_fill`, `widgets.hovered.bg_fill`, `text_color`, `warn_fg_color`, and `error_fg_color`. This ensures that grid rendering, background fills, and text elements adapt naturally to any selected theme.

## 2026-05-20 - Toast and AppUI Hardcoded Colors
**Erkenntnis:** Found that `ToastManager` in `toast.rs` used hardcoded `Color32::from_rgb` for different toast types and alpha backgrounds. `AppUI` in `app_ui.rs` used `Color32::YELLOW` and `Color32::GREEN` for visual feedback elements. This breaks contrast and visual unity across custom themes. Because egui lacks a standard success visual variable, we fallback to our custom mint accent.
**Aktion:** Replaced hardcoded info/warning/error colors with `ui.visuals().hyperlink_color`, `warn_fg_color`, and `error_fg_color`. Success colors replaced with `crate::core::theme::colors::MINT_ACCENT`. Alpha background fills replaced using `gamma_multiply` on `extreme_bg_color`. Always rely on `ui.visuals()` or `theme::colors` even for transient visual feedback or toasts.
