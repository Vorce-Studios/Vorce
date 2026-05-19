//! App actions for project.

use crate::app::core::app_struct::App;
use crate::orchestration::node_logic::load_project_file;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
use rfd::FileDialog;
use std::path::PathBuf;
use tracing::{error, info};
use vorce_io::save_project;
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, _needs_sync: &mut bool) -> bool {
    match action {
        UIAction::Export => {
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
        UIAction::SaveProjectAs => {
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
        UIAction::SaveProject(path_str) => {
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
        UIAction::LoadProject(path_str) => {
            let path = if path_str.is_empty() {
                if let Some(path) = FileDialog::new()
                    .add_filter("Vorce Project", &["vorce", "ron", "json"])
                    .pick_file()
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
        UIAction::LoadRecentProject(path_str) => {
            let path = PathBuf::from(path_str);
            let _ = load_project_file(app, &path);
        }
        UIAction::Exit => {
            info!("Exit requested via menu");
            app.exit_requested = true;
        }
        UIAction::OpenSettings => {
            info!("Settings requested");
            app.ui_state.show_settings = true;
        }
        UIAction::OpenAbout => {
            info!("About dialog requested");
            app.ui_state.show_about = true;
        }
        UIAction::OpenLicense => {
            app.egui_context.open_url(egui::OpenUrl::new_tab(
                "https://github.com/Vorce-Studios/Vorce/blob/main/LICENSE",
            ));
        }
        _ => return false,
    }
    true
}
