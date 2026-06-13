//! NDI input and status action handlers.

#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

/// Handles retrieving NDI sender status.
pub fn handle_get_ndi_sender_status(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::GetNdiSenderStatus(part_id, sender) = action {
        // NDI status implementation
    }
}

#[cfg(feature = "ndi")]
/// Handles connecting to an NDI source.
pub fn handle_connect_ndi_source(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ConnectNdiSource { layer_id, source_name } = action {
        // NDI connection implementation
    }
}

#[cfg(feature = "ndi")]
/// Handles disconnecting from an NDI source.
pub fn handle_disconnect_ndi_source(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::DisconnectNdiSource { layer_id } = action {
        // NDI disconnection implementation
    }
}
