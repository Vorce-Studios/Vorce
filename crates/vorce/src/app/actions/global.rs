#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use tracing::info;
use vorce_ui::UIAction;

pub fn handle_set_global_fullscreen(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetGlobalFullscreen(is_fullscreen) = action {
        *_needs_sync = true;
        // Update config
        app.ui_state.user_config.global_fullscreen = is_fullscreen;
        let _ = app.ui_state.user_config.save();
        info!("Global fullscreen set to: {}", is_fullscreen);
    }
}

pub fn handle_open_shader_graph(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::OpenShaderGraph(graph_id) = action {
        app.ui_state.show_shader_graph = true;
        if let Some(graph) = app.state.shader_graphs.get(&graph_id) {
            app.ui_state.node_editor_panel.load_graph(graph);
        } else {
            // Create if not exists
            if let std::collections::hash_map::Entry::Vacant(e) =
                app.state.shader_graphs_mut().entry(graph_id)
            {
                let new_graph =
                    vorce_core::shader_graph::ShaderGraph::new(graph_id, "New Graph".to_string());
                e.insert(new_graph.clone());
                app.ui_state.node_editor_panel.load_graph(&new_graph);
            }
        }
    }
}

pub fn handle_toggle_module_canvas(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleModuleCanvas = action {
        app.ui_state.show_module_canvas = !app.ui_state.show_module_canvas;
    }
}

pub fn handle_toggle_fullscreen(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleFullscreen = action {
        app.ui_state.user_config.window_maximized = !app.ui_state.user_config.window_maximized;
        let _ = app.ui_state.user_config.save();
    }
}

pub fn handle_toggle_controller_overlay(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleControllerOverlay = action {
        app.ui_state.show_controller_overlay = !app.ui_state.show_controller_overlay;
    }
}

pub fn handle_reset_layout(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ResetLayout = action {
        let active_layout_id = app.ui_state.user_config.active_layout_id.clone();
        if let Some(layout) = app.ui_state.user_config.active_layout_mut() {
            *layout = vorce_ui::core::config::LayoutProfile::default_profile();
            layout.id = active_layout_id;
        }
        app.ui_state.apply_active_layout();
        app.ui_state.show_stats = true;
        app.ui_state.show_master_controls = true;
    }
}

pub fn handle_toggle_media_manager(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleMediaManager = action {
        app.media_manager_ui.visible = !app.media_manager_ui.visible;
    }
}

pub fn handle_exit(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Exit = action {
        info!("Exit requested via menu");
        app.exit_requested = true;
    }
}

pub fn handle_open_settings(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::OpenSettings = action {
        info!("Settings requested");
        app.ui_state.show_settings = true;
    }
}

pub fn handle_open_about(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::OpenAbout = action {
        info!("About dialog requested");
        app.ui_state.show_about = true;
    }
}

pub fn handle_open_license(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::OpenLicense = action {
        app.egui_context.open_url(egui::OpenUrl::new_tab(
            "https://github.com/Vorce-Studios/Vorce/blob/main/LICENSE",
        ));
    }
}

pub fn handle_toggle_midi_learn(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleMidiLearn = action {
        app.ui_state.is_midi_learn_mode = !app.ui_state.is_midi_learn_mode;
        info!("MIDI Learn mode: {}", app.ui_state.is_midi_learn_mode);
    }
}

pub fn handle_toggle_audio_panel(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleAudioPanel = action {
        app.ui_state.show_audio = !app.ui_state.show_audio;
    }
}
