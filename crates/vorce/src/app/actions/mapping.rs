//! Input mapping and paint action handlers.

#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_core::{mapping::Mapping, paint::Paint};
use vorce_ui::UIAction;

/// Handles adding a new paint.
pub fn handle_add_paint(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::AddPaint = action {
        let count = app.state.paint_manager.paints().len();
        app.state
            .paint_manager_mut()
            .add_paint(Paint::test_pattern(0, format!("Paint {}", count + 1)));
        app.state.dirty = true;
    }
}

/// Handles removing a paint.
pub fn handle_remove_paint(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RemovePaint(id) = action {
        app.state.paint_manager_mut().remove_paint(id);
        app.state.dirty = true;
    }
}

/// Handles adding a new mapping.
pub fn handle_add_mapping(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::AddMapping = action {
        let count = app.state.mapping_manager.mappings().len();
        app.state.mapping_manager_mut().add_mapping(Mapping::quad(
            0,
            format!("Mapping {}", count + 1),
            0,
        ));
        app.state.dirty = true;
    }
}

/// Handles removing a mapping.
pub fn handle_remove_mapping(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RemoveMapping(id) = action {
        app.state.mapping_manager_mut().remove_mapping(id);
        app.state.dirty = true;
    }
}

/// Handles selecting a mapping.
pub fn handle_select_mapping(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SelectMapping(id) = action {
        app.ui_state.selected_layer_id = Some(id);
    }
}

/// Handles toggling mapping visibility.
pub fn handle_toggle_mapping_visibility(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleMappingVisibility(id, visible) = action {
        if let Some(mapping) = app.state.mapping_manager_mut().get_mapping_mut(id) {
            mapping.visible = visible;
            app.state.dirty = true;
        }
    }
}

/// Handles updating mapping mesh.
pub fn handle_update_mapping_mesh(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::UpdateMappingMesh(id, mesh) = action {
        if let Some(mapping) = app.state.mapping_manager_mut().get_mapping_mut(id) {
            mapping.mesh = mesh;
            app.state.dirty = true;
        }
    }
}
