## 2024-05-18 – Standardize info labels and empty states
**Learning:** Hardcoded, inline `egui::RichText::new(...).weak().italics()` calls lead to spaghetti dependencies when panels try to reuse an inspector's internal style, and create inconsistencies if not properly centralized.
**Action:** Always use the globally accessible `crate::widgets::custom::render_info_label` and `crate::widgets::custom::render_missing_preview_banner` for empty states across panels to maintain a clean UI architecture and consistent styling.
