//! App actions for settings.

use crate::app::core::app_struct::App;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
use tracing::info;
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, needs_sync: &mut bool) -> bool {
    match action {
        UIAction::SelectAudioDevice(device) => {
            app.ui_state.selected_audio_device = Some(device.clone());
            app.ui_state.user_config.selected_audio_device = Some(device.clone());
            app.state.dirty = true;
            let _ = app.ui_state.user_config.save();
            info!("Selected audio device: {:?}", app.ui_state.selected_audio_device);
        }
        UIAction::UpdateAudioConfig(cfg) => {
            app.state.audio_config = cfg.clone();
            app.audio_analyzer.update_config(cfg);
            app.state.dirty = true;
            // Persistence fix for MF-035
            let _ = app.ui_state.user_config.save();
        }
        // Settings
        UIAction::SetTargetFps(fps) => {
            app.ui_state.user_config.target_fps = Some(fps);
            let _ = app.ui_state.user_config.save();
            app.ui_state.target_fps = fps; // Keep runtime variable updated if necessary
        }
        UIAction::SetVsyncMode(mode) => {
            app.ui_state.user_config.vsync_mode = mode;
            let _ = app.ui_state.user_config.save();
            // Apply vsync right away
            app.window_manager.update_vsync_mode(&app.backend, mode);
        }
        UIAction::SetPreferredGpu(gpu) => {
            app.ui_state.user_config.preferred_gpu = gpu;
            let _ = app.ui_state.user_config.save();
        }

        // Global Fullscreen Setting
        UIAction::SetGlobalFullscreen(is_fullscreen) => {
            *needs_sync = true;
            // Update config
            app.ui_state.user_config.global_fullscreen = is_fullscreen;
            let _ = app.ui_state.user_config.save();
            info!("Global fullscreen set to: {}", is_fullscreen);
        }
        UIAction::OpenShaderGraph(graph_id) => {
            app.ui_state.show_shader_graph = true;
            if let Some(graph) = app.state.shader_graphs.get(&graph_id) {
                app.ui_state.node_editor_panel.load_graph(graph);
            } else {
                // Create if not exists
                if let std::collections::hash_map::Entry::Vacant(e) =
                    app.state.shader_graphs_mut().entry(graph_id)
                {
                    let new_graph = vorce_core::shader_graph::ShaderGraph::new(
                        graph_id,
                        "New Graph".to_string(),
                    );
                    e.insert(new_graph.clone());
                    app.ui_state.node_editor_panel.load_graph(&new_graph);
                }
            }
        }
        UIAction::ToggleModuleCanvas => {
            app.ui_state.show_module_canvas = !app.ui_state.show_module_canvas;
        }
        UIAction::ToggleFullscreen => {
            app.ui_state.user_config.window_maximized = !app.ui_state.user_config.window_maximized;
            let _ = app.ui_state.user_config.save();
        }
        UIAction::ToggleControllerOverlay => {
            app.ui_state.show_controller_overlay = !app.ui_state.show_controller_overlay;
        }
        UIAction::ResetLayout => {
            let active_layout_id = app.ui_state.user_config.active_layout_id.clone();
            if let Some(layout) = app.ui_state.user_config.active_layout_mut() {
                *layout = vorce_ui::core::config::LayoutProfile::default_profile();
                layout.id = active_layout_id;
            }
            app.ui_state.apply_active_layout();
            app.ui_state.show_stats = true;
            app.ui_state.show_master_controls = true;
        }
        UIAction::SetLanguage(lang_code) => {
            app.state.settings_mut().language = lang_code.clone();
            app.state.dirty = true;
            app.ui_state.i18n.set_locale(&lang_code);
            info!("Language switched to: {}", lang_code);
        }
        UIAction::SetMeterStyle(style) => {
            app.ui_state.user_config.meter_style = style;
            app.state.dirty = true;
            let _ = app.ui_state.user_config.save();
            info!("Audio meter style switched to: {:?}", style);
        }
        UIAction::ToggleMidiLearn => {
            app.ui_state.is_midi_learn_mode = !app.ui_state.is_midi_learn_mode;
            info!("MIDI Learn mode: {}", app.ui_state.is_midi_learn_mode);
        }
        UIAction::ToggleAudioPanel => {
            app.ui_state.show_audio = !app.ui_state.show_audio;
        }
        UIAction::ToggleMediaManager => {
            app.media_manager_ui.visible = !app.media_manager_ui.visible;
        }
        _ => return false,
    }
    true
}
