#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_mcp::McpAction;
use vorce_ui::UIAction;

pub fn handle_get_ndi_sender_status(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::GetNdiSenderStatus(part_id, tx) = action {
        let _ = app.action_sender.send(McpAction::GetNdiSenderStatus(part_id, tx));
    }
}

#[cfg(feature = "ndi")]
pub fn handle_connect_ndi_source(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ConnectNdiSource { part_id, source } = action {
        if !app.ndi_receivers.contains_key(&part_id) {
            info!("Creating new NdiReceiver for part {}", part_id);
            match vorce_io::ndi::NdiReceiver::new() {
                Ok(receiver) => {
                    app.ndi_receivers.insert(part_id, receiver);
                }
                Err(e) => {
                    error!("Failed to create NDI receiver: {}", e);
                    return;
                }
            }
        }
        if let Some(receiver) = app.ndi_receivers.get_mut(&part_id) {
            info!("Connecting part {} to NDI source '{}'", part_id, source.name);
            if let Err(e) = receiver.connect(&source) {
                error!("Failed to connect to NDI source: {}", e);
            }
        }
    }
}

#[cfg(feature = "ndi")]
pub fn handle_disconnect_ndi_source(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::DisconnectNdiSource { part_id } = action {
        info!("Disconnecting NDI source from part {}", part_id);
        app.ndi_receivers.remove(&part_id);
    }
}
