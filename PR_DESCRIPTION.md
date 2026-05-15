## 🎯 What

Extracted the `labeled_row` helper function from `transform_panel.rs` into the shared `widgets::custom` module and exposed it as public.

## 💡 Why

The `labeled_row` function implements a common UI pattern (a label with right-aligned content) that is generally useful across multiple panels and views, rather than being strictly tied to the Transform panel. Moving it to the shared custom widgets module reduces duplication and promotes reuse.

## ✅ Verification

1. Extracted the function cleanly into `custom.rs`.
2. Replaced the local usage in `transform_panel.rs` with an import.
3. Formatted code via `cargo fmt`.
4. Verified linting via `cargo clippy` without warnings.
5. Successfully ran the test suite (`cargo test -p vorce-ui`) to ensure no regressions.

## ✨ Result

Improved code modularity and maintainability by making a common egui layout pattern reusable across the application's UI components without code duplication.

## Verlinktes Issue

Fixes #000
