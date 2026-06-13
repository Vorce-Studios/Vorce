#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

/// Sets the opacity of a layer by its ID.
pub fn handle_set_layer_opacity(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLayerOpacity(id, opacity) = action {
        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.opacity = opacity;
            app.state.dirty = true;
        }
    }
}

/// Sets the blend mode of a layer by its ID.
pub fn handle_set_layer_blend_mode(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLayerBlendMode(id, mode) = action {
        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.blend_mode = mode;
            app.state.dirty = true;
        }
    }
}

/// Sets whether a layer is visible.
pub fn handle_set_layer_visibility(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLayerVisibility(id, visible) = action {
        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.visible = visible;
            app.state.dirty = true;
        }
    }
}

/// Adds a new layer to the layer manager.
pub fn handle_add_layer(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::AddLayer = action {
        let count = app.state.layer_manager.len();
        app.state.layer_manager_mut().create_layer(format!("Layer {}", count + 1));
        app.state.dirty = true;
    }
}

/// Creates a new layer group.
pub fn handle_create_group(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::CreateGroup = action {
        let count = app.state.layer_manager.len();
        app.state.layer_manager_mut().create_group(format!("Group {}", count + 1));
        app.state.dirty = true;
    }
}

/// Reparents a layer to a different group or the root.
pub fn handle_reparent_layer(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ReparentLayer(id, parent_id) = action {
        app.state.layer_manager_mut().reparent_layer(id, parent_id);
        app.state.dirty = true;
    }
}

/// Swaps the positions/ordering of two layers.
pub fn handle_swap_layers(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SwapLayers(id1, id2) = action {
        app.state.layer_manager_mut().swap_layers(id1, id2);
        app.state.dirty = true;
    }
}

/// Toggles whether a layer group is collapsed in the UI list.
pub fn handle_toggle_group_collapsed(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleGroupCollapsed(id) = action {
        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.collapsed = !layer.collapsed;
            app.state.dirty = true;
        }
    }
}

/// Removes a layer from the layer manager.
pub fn handle_remove_layer(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RemoveLayer(id) = action {
        app.state.layer_manager_mut().remove_layer(id);
        app.state.dirty = true;
        if app.ui_state.selected_layer_id == Some(id) {
            app.ui_state.selected_layer_id = None;
        }
    }
}

/// Duplicates an existing layer.
pub fn handle_duplicate_layer(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::DuplicateLayer(id) = action {
        if let Some(new_id) = app.state.layer_manager_mut().duplicate_layer(id) {
            app.ui_state.selected_layer_id = Some(new_id);
            app.state.dirty = true;
        }
    }
}

/// Toggles whether a layer is soloed.
pub fn handle_toggle_layer_solo(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleLayerSolo(id) = action {
        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.toggle_solo();
            app.state.dirty = true;
        }
    }
}

/// Toggles whether a layer is bypassed (ignored during rendering).
pub fn handle_toggle_layer_bypass(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ToggleLayerBypass(id) = action {
        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.toggle_bypass();
            app.state.dirty = true;
        }
    }
}

/// Ejects/unloads media from all layers.
pub fn handle_eject_all_layers(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::EjectAllLayers = action {
        app.state.layer_manager_mut().eject_all();
        app.state.dirty = true;
    }
}

/// Sets the transform (position, scale, rotation) of a layer.
pub fn handle_set_layer_transform(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLayerTransform(id, transform) = action {
        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.transform = transform;
            app.state.dirty = true;
        }
    }
}

/// Applies a specific resize mode to adapt the layer size to the composition bounds.
pub fn handle_apply_resize_mode(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ApplyResizeMode(id, mode) = action {
        let target_size = vorce_core::Vec2::new(
            app.state.layer_manager.composition.size.0 as f32,
            app.state.layer_manager.composition.size.1 as f32,
        );

        let mut source_size = vorce_core::Vec2::ONE;
        if let Some(layer) = app.state.layer_manager.get_layer(id) {
            if let Some(paint_id) = layer.paint_id {
                if let Some(_paint) = app.state.paint_manager.get_paint(paint_id) {
                    source_size = target_size;
                }
            }
        }

        if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
            layer.set_transform_with_resize(mode, source_size, target_size);
            app.state.dirty = true;
        }
    }
}

/// Renames a layer by its ID.
pub fn handle_rename_layer(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::RenameLayer(id, name) = action {
        app.state.layer_manager_mut().rename_layer(id, name);
        app.state.dirty = true;
    }
}
