#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use tracing::info;
use vorce_ui::UIAction;

/// Adds a new projection output target.
pub fn handle_add_output(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::AddOutput(name, region, size) = action {
        app.history.push(app.state.clone());
        app.state.output_manager_mut().add_output(name, region, size);
        app.state.dirty = true;
    }
}

/// Removes a projection output target by its ID.
pub fn handle_remove_output(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RemoveOutput(id) = action {
        app.history.push(app.state.clone());
        app.state.output_manager_mut().remove_output(id);
        app.state.dirty = true;
    }
}

/// Configures properties (fullscreen, display, resolution) of a projection output target.
pub fn handle_configure_output(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ConfigureOutput(id, config) = action {
        let fs = config.fullscreen;
        app.state.output_manager_mut().update_output(id, config.clone());

        let all_ids: Vec<_> =
            app.state.output_manager.list_outputs().iter().map(|o| o.id).collect();
        for oid in all_ids {
            if let Some(other) = app.state.output_manager_mut().get_output_mut(oid) {
                if other.fullscreen != fs {
                    other.fullscreen = fs;
                    info!("Syncing fullscreen state for output {} -> {}", oid, fs);
                }
            }
        }

        app.state.dirty = true;
    }
}
