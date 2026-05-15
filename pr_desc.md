## 🧹 Code Health Improvement

**🎯 What:**
Migrated Timeline show-control models (`ShowMode`, `ModuleArrangementItem`) and state out of `TimelineV2` UI-state directly into a newly isolated `ShowControlModel` which is tracked as a persistent, serialized part of `AppState`.

**💡 Why:**
The timeline show-control data must survive save/load cycles and not leak across project-switches. Previously, runtime UI states mixed with persistent orchestration configuration within the `TimelineV2` panel widget structure, completely bypassing disk I/O save/load roundtrips and undo history.

**✅ Verification:**
- Successfully passed `cargo check` and `cargo test --workspace`.
- Unit tests accurately interact with `ShowControlModel` for correct arrangement handling.
- `app.ui_state.timeline_panel` transient parameters are cleanly scrubbed to defaults on `load_project_file`.

**✨ Result:**
Loading a project effectively restores exact show-control data while correctly disregarding the previous project's runtime data. Any interaction mutating `ShowControlModel` securely evaluates to the `dirty` flag and tracks application state edits properly.

## Verlinktes Issue
Fixes #96
