# MapFlow: Technical Debt, Bugs and Roadmap Gaps

This document tracks the current state of MapFlow's implementation, identifying critical architectural issues, incomplete features, and technical debt.

---

## 🛑 Critical Architectural Issues

| Issue | Status | Impact | File/Location |
| :--- | :--- | :--- | :--- |
| **"God Object" module_canvas** | ✅ Completed | `module_canvas` has been split into `controller.rs`, `draw.rs`, `state.rs`, `types.rs`, etc. God object eliminated. | `crates/mapmap-ui/src/editors/module_canvas/` |
| **Monolithic core/module.rs** | ✅ Completed | Refactor completed (2026-02-27). Split into `types.rs`, `config.rs`, `manager.rs`, and `mod.rs`. | `crates/mapmap-core/src/module/` |
| **GPU Upload Blockage** | ✅ Fixed | Threaded uploads implemented in `FramePipeline` (PR #831 and #871). Micro-stutters resolved. | `crates/mapmap/src/orchestration/media.rs` |
| **wgpu Lifetime Hack** | 🟡 In Progress | Unsafe `transmute` still used in `render.rs` (L501) for `egui-wgpu` static lifetimes. | `crates/mapmap/src/app/loops/render.rs` |
| **UI App Pointer Hack** | 🟡 Partial Fix | Raw pointers minimized, but complex mutable `&mut App` passing still dominates the render loop. | `crates/mapmap/src/app/loops/render.rs` |

---

## 🎨 Feature Gaps: Code vs. UI (Updated)

- **NDI Support**: 🟡 Partial. `NdiSender` implemented; `NdiReceiver` is missing in `mapmap-media` and `orchestration`.
- **MPV Decoder**: 🟡 Partial Fix. Integrated via `libmpv2`, but uses `screenshot-raw` (L113) with CPU-side RGBA conversion instead of native GPU sharing.
- **Link System**: ✅ Integrated (PR #837). UI for linking nodes is functional.
- **Bevy Node Controls**: 🔴 Missing. UI labels (L915) explicitly state controls for Bevy Particles, Atmosphere, and HexGrid are "not yet implemented".
- **HAP Video Alpha**: Alpha support is partially implemented. HAP Q Alpha (YCoCg+A) is currently a TODO. Complex multi-section decoding is unstable.
- **Shader Graph Nodes**: Core supports logic nodes, but UI lacks visual representation/wiring for complex operations.
- **LUT Support**: No "LUT Effect" node in the effect chain UI despite core support.
- **SRT Streaming**: Missing `libsrt` integration; connection/sending logic are just stubs.
- **OSC Triggers**: UI lacks OSC input field for Cue triggers.
- **Philips Hue**: 🟡 Partial. `HueOutput` params added to core (L513), but pairing logic and Area Selection fetching are missing.

---

## 🛠️ Significant Technical Debt (TODOs)

### 🏗️ Architecture & Core Logic
- **Undo/Redo Coverage**: Currently stores full `AppState` snapshots. Needs granular commands for parameters, connections, and layer mutations to reduce memory pressure.
- **Trigger Smoothing**: 🔴 Incomplete. `TriggerMappingMode::Smoothed` exists in `trigger.rs` (L51), but evaluation (L125) performs only linear mapping; Attack/Release logic is missing.
- **Individual Layer Speed**: 🔴 Missing. `LayerType` (layer.rs) lacks speed parameters; evaluation defaults to master speed.
- **Mesh Import**: 🔴 Missing. `MeshType` supports `Custom { path }` (L139), but `to_mesh()` has no loader for OBJ/SVG files.
- **Shader Codegen**: 🟡 Partial. Code generator lacks scale, rotation, and translation parameter injection (L517).
- **Graph Validation**: 🔴 Missing. `shader_graph.rs` (L529) lacks cycle detection and type-safety checks.
- **MCP Shared State**: 🔴 Missing. `server.rs` (L722) contains a hardcoded error for shared state access.
- **Spout Sync**: 🔴 Missing. Spout output (L129) is explicitly excluded from the main synchronization loop in `orchestration/outputs.rs`.

### 🧼 Code Cleanup & Quality
- **Panic Policy**: Replace `panic!` and `.unwrap()` in `mapmap-mcp/server.rs` (L1235+), `web/handlers.rs`, and MIDI mapping.
- **Safety Documentation**: Every `unsafe` block must have a `// SAFETY:` comment (especially in FFmpeg/NDI/Spout).
- **Dead Code**: Significant amounts of legacy Qt-migration logic in `window_manager.rs` and `mesh_editor.rs`.
- **Media Thumbnails**: Background thumbnail generation and duration extraction missing in `media_browser.rs`.

---

## 🐛 Known Bugs

| Bug | Status | Root Cause |
| :--- | :--- | :--- |
| **Output Magenta Patterns** | 🟡 Partial Fix | `PaintTextureCache` falls back to test pattern because real loading is missing. |
| **NDI Buffer Padding** | 🟡 In Progress | Hardcoded 256-byte alignment in NDI readback may fail on some hardware. |
| **Theme Switching** | 🔴 Missing | Global theme application requires restart; `settings.rs` implementation missing. |
| **Node Renaming** | ✅ Fixed | Rename/Duplicate actions enabled in `module_sidebar.rs`. |
| **Canvas Toolbar Lag** | ✅ Fixed | Restored with modern egui API in commit 56d67ed3. |

---

*Last Updated: 2026-02-27 (by Orchestrator) 🦀*
