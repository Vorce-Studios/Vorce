//! Output configuration and management action handlers.

#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

/// Handles adding a new output.
pub fn handle_add_output(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::AddOutput(name, region, res) = action {
        app.state.output_manager_mut().add_output(name, region, res);
        app.state.dirty = true;
    }
}

/// Handles removing an output.
pub fn handle_remove_output(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RemoveOutput(id) = action {
        app.state.output_manager_mut().remove_output(id);
        app.state.dirty = true;
    }
}

/// Handles configuring output properties.
pub fn handle_configure_output(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ConfigureOutput(id, config) = action {
        app.state.output_manager_mut().update_output(id, config);
        app.state.dirty = true;
    }
}
