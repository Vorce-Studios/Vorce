//! App actions for layer.

use crate::app::core::app_struct::App;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, _needs_sync: &mut bool) -> bool {
    match action {
        UIAction::SetLayerOpacity(id, opacity) => {
            if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
                layer.opacity = opacity;
                app.state.dirty = true;
            }
        }
        UIAction::SetLayerBlendMode(id, mode) => {
            if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
                layer.blend_mode = mode;
                app.state.dirty = true;
            }
        }
        UIAction::SetLayerVisibility(id, visible) => {
            if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
                layer.visible = visible;
                app.state.dirty = true;
            }
        }
        UIAction::AddLayer => {
            let count = app.state.layer_manager.len();
            app.state.layer_manager_mut().create_layer(format!("Layer {}", count + 1));
            app.state.dirty = true;
        }
        UIAction::CreateGroup => {
            let count = app.state.layer_manager.len();
            app.state.layer_manager_mut().create_group(format!("Group {}", count + 1));
            app.state.dirty = true;
        }
        UIAction::ReparentLayer(id, parent_id) => {
            app.state.layer_manager_mut().reparent_layer(id, parent_id);
            app.state.dirty = true;
        }
        UIAction::SwapLayers(id1, id2) => {
            app.state.layer_manager_mut().swap_layers(id1, id2);
            app.state.dirty = true;
        }
        UIAction::ToggleGroupCollapsed(id) => {
            if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
                layer.collapsed = !layer.collapsed;
                app.state.dirty = true;
            }
        }
        UIAction::RemoveLayer(id) => {
            app.state.layer_manager_mut().remove_layer(id);
            app.state.dirty = true;
            if app.ui_state.selected_layer_id == Some(id) {
                app.ui_state.selected_layer_id = None;
            }
        }
        UIAction::DuplicateLayer(id) => {
            if let Some(new_id) = app.state.layer_manager_mut().duplicate_layer(id) {
                app.ui_state.selected_layer_id = Some(new_id);
                app.state.dirty = true;
            }
        }
        UIAction::RenameLayer(id, name)
            if app.state.layer_manager_mut().rename_layer(id, name.clone()) =>
        {
            app.state.dirty = true;
        }
        UIAction::ToggleLayerSolo(id) => {
            if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
                layer.toggle_solo();
                app.state.dirty = true;
            }
        }
        UIAction::ToggleLayerBypass(id) => {
            if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
                layer.toggle_bypass();
                app.state.dirty = true;
            }
        }
        UIAction::EjectAllLayers => {
            app.state.layer_manager_mut().eject_all();
            app.state.dirty = true;
        }
        UIAction::SetLayerTransform(id, transform) => {
            if let Some(layer) = app.state.layer_manager_mut().get_layer_mut(id) {
                layer.transform = transform;
                app.state.dirty = true;
            }
        }
        UIAction::ApplyResizeMode(id, mode) => {
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
        _ => return false,
    }
    true
}
