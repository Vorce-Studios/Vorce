## 2025-06-13 - [egui] Adding Tooltips to Icon-Only Buttons
**Learning:** In the `egui` framework, generic symbolic buttons (like `+`, `-`, or `✕`) lack inherent context for screen readers and users who may not understand the icon's intent. The framework allows chaining methods directly to the UI elements to provide this context without disrupting layout.
**Action:** Always chain the `.on_hover_text("...")` method directly to the `ui.button(...)` call for any icon-only or generic symbolic buttons to ensure accessibility and an intuitive UX.
