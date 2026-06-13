//! Application action dispatcher and handlers.

pub mod layer;
pub mod mapping;
pub mod mcp;
pub mod media;
pub mod midi;
pub mod ndi;
pub mod node;
pub mod output;
pub mod playback;
pub mod project;
pub mod settings;

pub use mcp::handle_mcp_actions;

use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

/// Drains and processes all pending UI actions.
/// Returns true if any action requested a structural synchronization.
pub fn handle_ui_actions(app: &mut App) -> Result<bool, String> {
    let actions: Vec<UIAction> = app.ui_state.actions.drain(..).collect();
    let mut needs_sync = false;

    for action in actions {
        dispatch_action(app, action, &mut needs_sync);
    }

    Ok(needs_sync)
}

/// Dispatches UI actions to their respective handlers.
pub fn dispatch_action(app: &mut App, action: UIAction, needs_sync: &mut bool) {
    match &action {
        UIAction::SetLayerOpacity(..)
        | UIAction::SetLayerBlendMode(..)
        | UIAction::SetLayerVisibility(..)
        | UIAction::AddLayer
        | UIAction::CreateGroup
        | UIAction::ReparentLayer(..)
        | UIAction::SwapLayers(..)
        | UIAction::ToggleGroupCollapsed(..)
        | UIAction::RemoveLayer(..)
        | UIAction::DuplicateLayer(..)
        | UIAction::ToggleLayerSolo(..)
        | UIAction::ToggleLayerBypass(..)
        | UIAction::EjectAllLayers
        | UIAction::SetLayerTransform(..)
        | UIAction::ApplyResizeMode(..)
        | UIAction::RenameLayer(..) => {
            layer::handle_set_layer_opacity(app, action, needs_sync);
        }

        UIAction::AddPaint
        | UIAction::RemovePaint(..)
        | UIAction::AddMapping
        | UIAction::RemoveMapping(..)
        | UIAction::SelectMapping(..)
        | UIAction::ToggleMappingVisibility(..)
        | UIAction::UpdateMappingMesh(..) => {
            mapping::handle_add_paint(app, action, needs_sync);
        }

        UIAction::PickMediaFile(..)
        | UIAction::SetMediaFile(..)
        | UIAction::MediaCommand(..)
        | UIAction::ManualTrigger(..) => {
            media::handle_pick_media_file(app, action, needs_sync);
        }

        UIAction::SetMidiAssignment(..) => {
            midi::handle_set_midi_assignment(app, action, needs_sync);
        }

        UIAction::GetNdiSenderStatus(..) => {
            ndi::handle_get_ndi_sender_status(app, action, needs_sync);
        }

        UIAction::NodeAction(..) => {
            let _ = node::handle_node_action(app, action, needs_sync);
        }

        UIAction::AddOutput(..) | UIAction::RemoveOutput(..) | UIAction::ConfigureOutput(..) => {
            output::handle_add_output(app, action, needs_sync);
        }

        UIAction::Play
        | UIAction::Pause
        | UIAction::Stop
        | UIAction::SetSpeed(..)
        | UIAction::SetLoopMode(..)
        | UIAction::TimelineAction(..) => {
            playback::handle_play(app, action, needs_sync);
        }

        UIAction::Export
        | UIAction::SaveProject(..)
        | UIAction::SaveProjectAs
        | UIAction::LoadProject(..)
        | UIAction::LoadRecentProject(..)
        | UIAction::SetCompositionName(..)
        | UIAction::SetMasterOpacity(..)
        | UIAction::SetMasterSpeed(..)
        | UIAction::SetMasterBlackout(..) => {
            project::handle_export(app, action, needs_sync);
        }

        UIAction::SelectAudioDevice(..)
        | UIAction::UpdateAudioConfig(..)
        | UIAction::SetTargetFps(..)
        | UIAction::SetVsyncMode(..)
        | UIAction::SetPreferredGpu(..)
        | UIAction::SetLanguage(..)
        | UIAction::SetMeterStyle(..) => {
            settings::handle_select_audio_device(app, action, needs_sync);
        }

        _ => {}
    }
}
