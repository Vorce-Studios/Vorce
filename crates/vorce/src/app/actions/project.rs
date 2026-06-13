//! Project management and export action handlers.

#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use std::path::PathBuf;
use tracing::{error, info};
use vorce_ui::UIAction;

/// Handles exporting the current project.
pub fn handle_export(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Export = action {
        info!("Exporting project...");
    }
}

/// Handles saving the project with a new name.
pub fn handle_save_project_as(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SaveProjectAs = action {
        if let Some(path) = rfd::FileDialog::new()
            .add_filter("Vorce Project", &["vorce", "json"])
            .save_file()
        {
            let path_str = path.to_string_lossy().to_string();
            app.ui_state.user_config.last_project = Some(path_str.clone());
            handle_save_project(app, UIAction::SaveProject(path_str), _needs_sync);
        }
    }
}

/// Handles saving the current project.
pub fn handle_save_project(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SaveProject(path_str) = action {
        info!("Saving project to: {}", path_str);
        let path = PathBuf::from(&path_str);
        match vorce_io::save_project(&app.state, &path) {
            Ok(_) => {
                info!("Project saved successfully.");
                app.state.dirty = false;
                app.ui_state.user_config.add_recent_file(&path_str);
                app.ui_state.user_config.last_project = Some(path_str);
                let _ = app.ui_state.user_config.save();
            }
            Err(e) => error!("Failed to save project: {}", e),
        }
    }
}

/// Handles loading a project from file.
pub fn handle_load_project(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::LoadProject(id) = action {
        if let Some(path) = rfd::FileDialog::new()
            .add_filter("Vorce Project", &["vorce", "json"])
            .pick_file()
        {
            let path_str = path.to_string_lossy().to_string();
            handle_load_recent_project(app, UIAction::LoadRecentProject(path_str), _needs_sync);
        }
    }
}

/// Handles loading a project from the recent list.
pub fn handle_load_recent_project(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::LoadRecentProject(path_str) = action {
        info!("Loading project: {}", path_str);
        let path = PathBuf::from(&path_str);
        match vorce_io::load_project(&path) {
            Ok(new_state) => {
                app.state = new_state;
                app.state.dirty = false;
                app.ui_state.user_config.add_recent_file(&path_str);
                app.ui_state.user_config.last_project = Some(path_str);
                let _ = app.ui_state.user_config.save();
            }
            Err(e) => error!("Failed to load project: {}", e),
        }
    }
}

/// Handles setting the composition name.
pub fn handle_set_composition_name(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetCompositionName(name) = action {
        app.state.layer_manager_mut().composition.name = name;
        app.state.dirty = true;
    }
}

/// Handles setting master opacity.
pub fn handle_set_master_opacity(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMasterOpacity(opacity) = action {
        app.state.layer_manager_mut().composition.master_opacity = opacity;
        app.state.dirty = true;
    }
}

/// Handles setting master speed.
pub fn handle_set_master_speed(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMasterSpeed(speed) = action {
        app.state.layer_manager_mut().composition.master_speed = speed;
        app.state.dirty = true;
    }
}

/// Handles setting master blackout mode.
pub fn handle_set_master_blackout(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMasterBlackout(blackout) = action {
        app.state.layer_manager_mut().composition.master_blackout = blackout;
        app.state.dirty = true;
    }
}
