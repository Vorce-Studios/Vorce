#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use crate::orchestration::node_logic::load_project_file;
use rfd::FileDialog;
use std::path::PathBuf;
use tracing::{error, info};
use vorce_io::save_project;
use vorce_ui::UIAction;

pub fn handle_export(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Export = action {
        if let Some(path) = FileDialog::new()
            .add_filter("Vorce Project Export", &["zip"])
            .set_file_name("project_export.zip")
            .save_file()
        {
            if let Err(e) = vorce_io::project::export_project(&app.state, &path) {
                error!("Failed to export project: {}", e);
            } else {
                info!("Project exported to {:?}", path);
            }
        }
    }
}

pub fn handle_save_project_as(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SaveProjectAs = action {
        if let Some(path) = FileDialog::new()
            .add_filter("Vorce Project", &["vorce", "ron", "json"])
            .set_file_name("project.vorce")
            .save_file()
        {
            if let Err(e) = save_project(&app.state, &path) {
                error!("Failed to save project: {}", e);
            } else {
                info!("Project saved to {:?}", path);
            }
        }
    }
}

pub fn handle_save_project(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SaveProject(path_str) = action {
        let path = if path_str.is_empty() {
            if let Some(path) = FileDialog::new()
                .add_filter("Vorce Project", &["vorce", "ron", "json"])
                .set_file_name("project.vorce")
                .save_file()
            {
                path
            } else {
                PathBuf::new()
            }
        } else {
            PathBuf::from(path_str)
        };

        if !path.as_os_str().is_empty() {
            if let Err(e) = save_project(&app.state, &path) {
                error!("Failed to save project: {}", e);
            } else {
                info!("Project saved to {:?}", path);
            }
        }
    }
}

pub fn handle_load_project(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::LoadProject(path_str) = action {
        let path = if path_str.is_empty() {
            if let Some(path) =
                FileDialog::new().add_filter("Vorce Project", &["vorce", "ron", "json"]).pick_file()
            {
                path
            } else {
                PathBuf::new()
            }
        } else {
            PathBuf::from(path_str)
        };

        if !path.as_os_str().is_empty() {
            let _ = load_project_file(app, &path);
        }
    }
}

pub fn handle_load_recent_project(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::LoadRecentProject(path_str) = action {
        let path = PathBuf::from(path_str);
        let _ = load_project_file(app, &path);
    }
}

pub fn handle_set_composition_name(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetCompositionName(name) = action {
        app.state.layer_manager_mut().composition.name = name;
        app.state.dirty = true;
    }
}

pub fn handle_set_master_opacity(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMasterOpacity(val) = action {
        app.state.layer_manager_mut().composition.set_master_opacity(val);
        app.state.dirty = true;
    }
}

pub fn handle_set_master_speed(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMasterSpeed(val) = action {
        app.state.layer_manager_mut().composition.set_master_speed(val);
        app.state.dirty = true;
    }
}

pub fn handle_set_master_blackout(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMasterBlackout(val) = action {
        app.state.layer_manager_mut().composition.master_blackout = val;
        app.state.dirty = true;
    }
}
