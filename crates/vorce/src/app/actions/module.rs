//! App actions for module.

use crate::app::core::app_struct::App;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
#[cfg(feature = "ndi")]
use tracing::{error, info};
use vorce_mcp::McpAction;
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, _needs_sync: &mut bool) -> bool {
    match action {
        UIAction::GetNdiSenderStatus(part_id, tx) => {
            let _ = app.action_sender.send(McpAction::GetNdiSenderStatus(part_id, tx));
        }
        #[cfg(feature = "ndi")]
        UIAction::ConnectNdiSource { part_id, source } => {
            let receiver = app.ndi_receivers.entry(part_id).or_insert_with(|| {
                info!("Creating new NdiReceiver for part {}", part_id);
                vorce_io::ndi::NdiReceiver::new().expect("Failed to create NDI receiver")
            });
            info!("Connecting part {} to NDI source '{}'", part_id, source.name);
            if let Err(e) = receiver.connect(&source) {
                error!("Failed to connect to NDI source: {}", e);
            }
        }

        #[cfg(feature = "ndi")]
        UIAction::DisconnectNdiSource { part_id } => {
            info!("Disconnecting NDI source from part {}", part_id);
            app.ndi_receivers.remove(&part_id);
        }
        UIAction::SetMidiAssignment(element_id, target_id) => {
            #[cfg(feature = "midi")]
            {
                use vorce_ui::config::MidiAssignmentTarget;
                app.ui_state.user_config.set_midi_assignment(
                    &element_id,
                    MidiAssignmentTarget::Vorce(target_id.clone()),
                );
                tracing::info!(
                    "MIDI Assignment set via Global Learn: {} -> {}",
                    element_id,
                    target_id
                );
            }
            #[cfg(not(feature = "midi"))]
            {
                let _ = element_id;
                let _ = target_id;
            }
        }
        _ => return false,
    }
    true
}
