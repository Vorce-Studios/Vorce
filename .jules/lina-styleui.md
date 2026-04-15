## 2024-05-18 - Replacing Hardcoded Colors with Theme Variables

**Erkenntnis:** Many UI components in `vorce-ui` (like `audio_meter.rs`, `custom.rs`, and `module_sidebar.rs`) use hardcoded colors such as `Color32::WHITE` for text. This breaks contrast when switching to light themes or different dark modes, as the text might become unreadable or lack visual harmony.

**Aktion:** Always use dynamic theme variables like `ui.visuals().text_color()` for text colors. This ensures consistency across all themes and avoids contrast issues when users change their theme. Avoid `Color32::WHITE` and other hardcoded colors whenever they are intended to render standard text or icons that should adapt to the theme.
