#![cfg(feature = "ndi")]
//! NDI Orchestration - Synchronizes NDI sources and senders with the module graph.

use crate::app::core::app_struct::App;
use tracing::{info, warn};
use vorce_core::module::{ModulePartType, OutputType, SourceType};

/// Synchronizes NDI receivers with the current module graph.
pub fn sync_ndi_receivers(app: &mut App) {
    let mut desired_ndi_sources = Vec::new();

    for module in app.state.module_manager.modules() {
        for part in &module.parts {
            if let ModulePartType::Source(SourceType::NdiInput { source_name }) = &part.part_type {
                if let Some(name) = source_name {
                    desired_ndi_sources.push((part.id, name.clone()));
                }
            }
        }
    }

    // Remove stale receivers
    let current_ids: Vec<_> = app.ndi_receivers.keys().cloned().collect();
    for id in current_ids {
        if !desired_ndi_sources.iter().any(|(pid, _)| *pid == id) {
            info!("Removing NDI receiver for part {}", id);
            app.ndi_receivers.remove(&id);
            app.texture_pool.release(&format!("part_{}", id));
        }
    }

    // Add new or update existing receivers
    for (part_id, source_name) in desired_ndi_sources {
        let needs_reconnect = if let Some(receiver) = app.ndi_receivers.get(&part_id) {
            receiver.source_name() != Some(source_name.as_str())
        } else {
            true
        };

        if needs_reconnect {
            info!("Connecting NDI receiver for part {} to {}", part_id, source_name);
            let mut receiver = match vorce_io::ndi::NdiReceiver::new() {
                Ok(r) => r,
                Err(e) => {
                    warn!("Failed to create NDI receiver: {}", e);
                    continue;
                }
            };

            let source = vorce_io::ndi::NdiSource { name: source_name.clone(), address: None };

            if let Err(e) = receiver.connect(&source) {
                warn!("Failed to connect NDI receiver: {}", e);
            }

            app.ndi_receivers.insert(part_id, receiver);
        }
    }
}

/// Synchronizes NDI senders with the current module graph.
pub fn sync_ndi_senders(app: &mut App) {
    let mut desired_senders = Vec::new();

    // Check dedicated NdiOutput nodes
    for module in app.state.module_manager.modules() {
        for part in &module.parts {
            if let ModulePartType::Output(OutputType::NdiOutput { name, width, height }) =
                &part.part_type
            {
                let stream_name =
                    if name.is_empty() { "Vorce NDI".to_string() } else { name.clone() };
                desired_senders.push((part.id, stream_name, *width, *height));
            }
            // Also handle Projectors with NDI enabled
            if let ModulePartType::Output(OutputType::Projector {
                ndi_enabled,
                ndi_stream_name,
                output_width,
                output_height,
                ..
            }) = &part.part_type
            {
                if *ndi_enabled {
                    desired_senders.push((
                        part.id,
                        ndi_stream_name.clone(),
                        *output_width,
                        *output_height,
                    ));
                }
            }
        }
    }

    // Remove stale senders
    let current_ids: Vec<_> = app.ndi_senders.keys().cloned().collect();
    for id in current_ids {
        if !desired_senders.iter().any(|(pid, ..)| *pid == id) {
            info!("Removing NDI sender for part {}", id);
            app.ndi_senders.remove(&id);
        }
    }

    // Add new or update existing senders
    for (part_id, name, width, height) in desired_senders {
        let needs_recreate = if let Some(sender) = app.ndi_senders.get(&part_id) {
            sender.name() != name.as_str()
            // Note: We don't currently expose format on sender to check resolution,
            // but NdiSender::new takes it. Recreating on name change for now.
        } else {
            true
        };

        if needs_recreate {
            info!(
                "Creating NDI sender for part {} with name {} ({}x{})",
                part_id, name, width, height
            );
            let format = vorce_io::format::VideoFormat::new(
                width.max(128),
                height.max(128),
                vorce_io::format::PixelFormat::BGRA8,
                60.0,
            );
            match vorce_io::ndi::NdiSender::new(name, format) {
                Ok(sender) => {
                    app.ndi_senders.insert(part_id, sender);
                }
                Err(e) => {
                    warn!("Failed to create NDI sender: {}", e);
                }
            }
        }
    }
}

/// Updates NDI sources by polling for new frames and uploading to GPU.
pub fn update_ndi_sources(app: &mut App) {
    use vorce_io::VideoSource;

    // We need to collect IDs to avoid multiple mutable borrows if we were to iterate directly
    let part_ids: Vec<_> = app.ndi_receivers.keys().cloned().collect();

    for part_id in part_ids {
        if let Some(receiver) = app.ndi_receivers.get_mut(&part_id) {
            match VideoSource::receive_frame(receiver) {
                Ok(frame) => {
                    let texture_name = format!("part_{}", part_id);
                    if let vorce_io::format::FrameData::Cpu(data) = frame.data {
                        app.texture_pool.upload_data(
                            &app.backend.queue,
                            &texture_name,
                            &data,
                            frame.format.width,
                            frame.format.height,
                        );
                    }
                }
                Err(vorce_io::error::IoError::NoFrameAvailable) => {}
                Err(e) => {
                    warn!("Error receiving NDI frame for part {}: {}", part_id, e);
                }
            }
        }
    }
}

/// Syncs NDI runtime status to UI canvas state so inspectors can reflect connection status.
pub fn sync_ndi_status_to_ui(app: &mut App) {
    use vorce_ui::editors::module_canvas::state::NdiInputStatus;

    // Update input status: reflect what receivers we have and their connected sources
    for (part_id, receiver) in &app.ndi_receivers {
        let status = NdiInputStatus {
            connected: receiver.source_name().is_some(),
            source_name: receiver.source_name().map(|s| s.to_string()),
            last_frame_time_ms: None,
        };
        app.ui_state.module_canvas.ndi_input_status.insert(*part_id, status);
    }

    // Remove status for parts that no longer have receivers
    app.ui_state
        .module_canvas
        .ndi_input_status
        .retain(|part_id, _| app.ndi_receivers.contains_key(part_id));

    // Update output status: reflect what senders we have (indicates active sending)
    for (part_id, _) in &app.ndi_senders {
        app.ui_state.module_canvas.ndi_output_status.insert(*part_id, true);
    }

    // Remove status for parts that no longer have senders
    app.ui_state
        .module_canvas
        .ndi_output_status
        .retain(|part_id, _| app.ndi_senders.contains_key(part_id));
}
