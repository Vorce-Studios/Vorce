//! App actions for master.

use crate::app::core::app_struct::App;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, _needs_sync: &mut bool) -> bool {
    match action {
        UIAction::SetMasterOpacity(val) => {
            app.state.layer_manager_mut().composition.set_master_opacity(val);
            app.state.dirty = true;
        }
        UIAction::SetMasterSpeed(val) => {
            app.state.layer_manager_mut().composition.set_master_speed(val);
            app.state.dirty = true;
        }
        UIAction::SetMasterBlackout(val) => {
            app.state.layer_manager_mut().composition.master_blackout = val;
            app.state.dirty = true;
        }
        UIAction::SetCompositionName(name) => {
            app.state.layer_manager_mut().composition.name = name;
            app.state.dirty = true;
        }
        UIAction::TimelineAction(timeline_action) => {
            use vorce_ui::TimelineAction;
            match timeline_action {
                TimelineAction::Play => app.state.effect_animator_mut().play(),
                TimelineAction::Pause => app.state.effect_animator_mut().pause(),
                TimelineAction::Stop => app.state.effect_animator_mut().stop(),
                TimelineAction::Seek(time) => app.state.effect_animator_mut().seek(time as f64),
                TimelineAction::SelectModule(module_id) => {
                    app.ui_state.module_canvas.set_active_module(Some(module_id))
                }
                TimelineAction::AddMarker(t) => {
                    let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                    let name = format!("Marker {:.1}s", t);
                    // Simple ID generation for markers
                    let id = (t * 1000.0) as u64;
                    animator.add_marker(vorce_core::animation::Marker::new(id, t as f64, name));
                }
                TimelineAction::RemoveMarker(t) => {
                    let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                    animator.remove_marker(t as f64);
                }
                TimelineAction::ToggleMarkerPause(t) => {
                    let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                    animator.toggle_marker_pause(t as f64);
                }
                TimelineAction::JumpNextMarker => {
                    let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                    animator.jump_next_marker();
                }
                TimelineAction::JumpPrevMarker => {
                    let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                    animator.jump_prev_marker();
                }
            }
        }
        _ => return false,
    }
    true
}
