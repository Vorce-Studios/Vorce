//! App actions for mapping.

use crate::app::core::app_struct::App;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
#[cfg(feature = "ndi")]
use tracing::{error, info};
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, _needs_sync: &mut bool) -> bool {
    match action {
        UIAction::AddPaint => {
            app.history.push(app.state.clone());
            let count = app.state.paint_manager.paints().len();
            app.state.paint_manager_mut().add_paint(vorce_core::Paint::color(
                0,
                format!("Paint {}", count + 1),
                [1.0, 1.0, 1.0, 1.0],
            ));
            app.state.dirty = true;
        }
        UIAction::RemovePaint(id) => {
            app.history.push(app.state.clone());
            app.state.paint_manager_mut().remove_paint(id);
            app.state.dirty = true;
        }
        UIAction::AddMapping => {
            app.history.push(app.state.clone());
            let count = app.state.mapping_manager.mappings().len();
            app.state.mapping_manager_mut().add_mapping(vorce_core::Mapping::quad(
                0,
                format!("Mapping {}", count + 1),
                0,
            ));
            app.state.dirty = true;
        }
        UIAction::RemoveMapping(id) => {
            app.history.push(app.state.clone());
            app.state.mapping_manager_mut().remove_mapping(id);
            app.state.dirty = true;
        }
        UIAction::SelectMapping(id) => {
            app.ui_state.selected_output_id = Some(id);
        }
        UIAction::ToggleMappingVisibility(id, visible) => {
            if let Some(mapping) = app.state.mapping_manager_mut().get_mapping_mut(id) {
                mapping.visible = visible;
                app.state.dirty = true;
            }
        }
        UIAction::UpdateMappingMesh(id, mesh) => {
            if let Some(mapping) =
                std::sync::Arc::make_mut(&mut app.state.mapping_manager).get_mapping_mut(id)
            {
                mapping.mesh = mesh;
                app.state.dirty = true;
            }
        }
        UIAction::AddOutput(name, region, size) => {
            app.history.push(app.state.clone());
            app.state.output_manager_mut().add_output(name, region, size);
            app.state.dirty = true;
        }
        UIAction::RemoveOutput(id) => {
            app.history.push(app.state.clone());
            app.state.output_manager_mut().remove_output(id);
            app.state.dirty = true;
        }

        #[cfg(feature = "ndi")]
        UIAction::ConfigureOutput(id, config) => {
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
        _ => return false,
    }
    true
}
