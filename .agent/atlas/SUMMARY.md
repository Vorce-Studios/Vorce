# Code Atlas Summary

- Crates indexed: 11
- Files indexed: 474

## Key Files

- `crates/vendor/egui_node_editor/src/color_hex_utils.rs`: rust-source containing _hex_dec, color_from_hex, color_to_hex (color_hex_utils, egui_node_editor, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/editor_ui.rs`: rust-source containing DISTANCE_TO_CONNECT, MAX_NODE_SIZE, NodeResponse (editor_ui, egui_node_editor, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/error.rs`: rust-source containing EguiGraphError (egui_node_editor, error, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/graph.rs`: rust-source containing InputParamKind, shown_inline_default, Graph (egui_node_editor, graph, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/graph_impls.rs`: rust-source containing add_connection, add_input_param, add_node (egui_node_editor, graph_impls, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/id_type.rs`: rust-source containing AnyParameterId, assume_input, assume_output (egui_node_editor, id_type, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/index_impls.rs`: rust-source containing index, index_mut, Output (egui_node_editor, index_impls, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/lib.rs`: rust-source containing color_hex_utils, editor_ui, error (egui_node_editor, lib, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/node_finder.rs`: rust-source containing new_at, show, NodeFinder (egui_node_editor, node_finder, rust-source, vendor)
- `crates/vendor/egui_node_editor/src/scale.rs`: rust-source containing scale, scaled, Scale (egui_node_editor, rust-source, scale, vendor)
- `crates/vendor/egui_node_editor/src/traits.rs`: rust-source containing all_kinds, bottom_ui, build_node (egui_node_editor, rust-source, traits, vendor)
- `crates/vendor/egui_node_editor/src/ui_state.rs`: rust-source containing MAX_ZOOM, MIN_ZOOM, _default_clip_rect (egui_node_editor, rust-source, ui_state, vendor)
- `crates/vendor/egui_node_editor/src/utils.rs`: rust-source containing lighten, ColorUtils (egui_node_editor, rust-source, utils, vendor)
- `crates/vorce-bevy/src/components.rs`: rust-source containing AudioReactiveSource, AudioReactiveTarget, BevyCameraMode (audio, components, rust-source, vorce-bevy, vorce_bevy)
- `crates/vorce-bevy/src/lib.rs`: Bevy integration for Vorce. This crate integrates the Bevy engine into Vorce to provide advanced 3D rendering capabilities. It bridges Vorce's core data structures with Bevy's ECS (Entity Component System), allowing f... (lib, rust-source, vorce-bevy, vorce_bevy)
- `crates/vorce-bevy/src/resources.rs`: rust-source containing get_energy, AudioInputResource, BevyNodeMapping (audio, resources, rust-source, vorce-bevy, vorce_bevy)
- `crates/vorce-bevy/src/systems.rs`: rust-source containing audio_reaction_system, camera_control_system, frame_readback_system (audio, rust-source, systems, vorce-bevy, vorce_bevy)
- `crates/vorce-control/src/cue/crossfade.rs`: Crossfade engine for smooth transitions between cues (crossfade, cue, rust-source, vorce-control, vorce_control)
- `crates/vorce-control/src/cue/cue.rs`: Cue definition and state A cue is a snapshot of the entire project state at a point in time. (cue, rust-source, vorce-control, vorce_control)
- `crates/vorce-control/src/cue/cue_list.rs`: Cue list management (cue, cue_list, rust-source, vorce-control, vorce_control)

## Usage

- `python scripts/dev-tools/generate-code-atlas.py`
- `python scripts/dev-tools/query-code-atlas.py "crate:vorce-core tag:evaluation"`
- `python scripts/dev-tools/query-code-atlas.py "symbol:ModuleEvaluator" --json`

