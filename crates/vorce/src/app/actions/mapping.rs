#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

/// Adds a new paint layer (color/source) to the paint manager.
pub fn handle_add_paint(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::AddPaint = action {
        app.history.push(app.state.clone());
        let count = app.state.paint_manager.paints().len();
        app.state.paint_manager_mut().add_paint(vorce_core::Paint::color(
            0,
            format!("Paint {}", count + 1),
            [1.0, 1.0, 1.0, 1.0],
        ));
        app.state.dirty = true;
    }
}

/// Removes a paint layer by its ID.
pub fn handle_remove_paint(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RemovePaint(id) = action {
        app.history.push(app.state.clone());
        app.state.paint_manager_mut().remove_paint(id);
        app.state.dirty = true;
    }
}

/// Adds a new projection mapping surface slice.
pub fn handle_add_mapping(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::AddMapping = action {
        app.history.push(app.state.clone());
        let count = app.state.mapping_manager.mappings().len();
        app.state.mapping_manager_mut().add_mapping(vorce_core::Mapping::quad(
            0,
            format!("Mapping {}", count + 1),
            0,
        ));
        app.state.dirty = true;
    }
}

/// Removes a projection mapping surface slice by its ID.
pub fn handle_remove_mapping(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RemoveMapping(id) = action {
        app.history.push(app.state.clone());
        app.state.mapping_manager_mut().remove_mapping(id);
        app.state.dirty = true;
    }
}

/// Selects a projection mapping slice in the editor interface.
pub fn handle_select_mapping(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SelectMapping(id) = action {
        app.ui_state.selected_output_id = Some(id);
    }
}

/// Toggles visibility of a projection mapping slice.
pub fn handle_toggle_mapping_visibility(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleMappingVisibility(id, visible) = action {
        if let Some(mapping) = app.state.mapping_manager_mut().get_mapping_mut(id) {
            mapping.visible = visible;
            app.state.dirty = true;
        }
    }
}

/// Updates the mesh geometry coordinates of a projection mapping slice.
pub fn handle_update_mapping_mesh(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::UpdateMappingMesh(id, mesh) = action {
        if let Some(mapping) =
            std::sync::Arc::make_mut(&mut app.state.mapping_manager).get_mapping_mut(id)
        {
            mapping.mesh = mesh;
            app.state.dirty = true;
        }
    }
}
