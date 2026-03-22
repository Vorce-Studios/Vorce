## 2024-05-18 – Standardize info labels and empty states
**Learning:** Hardcoded, inline `egui::RichText::new(...).weak().italics()` calls lead to spaghetti dependencies when panels try to reuse an inspector's internal style, and create inconsistencies if not properly centralized.
**Action:** Always use the globally accessible `crate::widgets::custom::render_info_label` and `crate::widgets::custom::render_missing_preview_banner` for empty states across panels to maintain a clean UI architecture and consistent styling.

## 2024-05-24 – Enhance visual feedback and accessibility for hold-to-action buttons
**Learning:** During stress or live-performance scenarios, missing visual confirmation when a "hold-to-confirm" action triggers makes the interface unpredictable. Also, using default generic text or `Debug` format enum strings inside `.widget_info` negatively affects screen reader usability.
**Action:** Ensure hold-to-confirm actions render a distinct 1-frame visual "flash" (like a full-width background fill or thicker border) when triggered (`progress >= 1.0`). Always map `hover_text` to the accessibility label via `WidgetInfo::labeled` instead of raw icon text to provide meaningful context for assistive technologies.
