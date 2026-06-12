use crate::app::core::app_struct::App;
use tracing::info;

pub fn handle_mcp_actions(app: &mut App) {
    while let Ok(action) = app.mcp_receiver.try_recv() {
        if let vorce_mcp::McpAction::GetProjectState(tx) = &action {
            tracing::info!("MCP: GetProjectState");
            match serde_json::to_string(&app.state) {
                Ok(json) => {
                    if let Err(e) = tx.send(json) {
                        tracing::error!("Failed to send project state back to MCP: {}", e);
                    }
                }
                Err(e) => {
                    tracing::error!("Failed to serialize project state for MCP: {}", e);
                    let _ = tx.send(format!("{{\"error\": \"Serialization failed: {e}\"}}"));
                }
            }
            continue;
        }
        if let vorce_mcp::McpAction::GetNdiSenderStatus(part_id, tx) = action {
            #[cfg(feature = "ndi")]
            {
                if let Some(sender) = app.ndi_senders.get(&part_id) {
                    let _ = tx.send(Some(sender.frame_count()));
                } else {
                    let _ = tx.send(None);
                }
            }
            #[cfg(not(feature = "ndi"))]
            {
                let _ = part_id;
                let _ = tx.send(None);
            }
            continue;
        }
        if let vorce_mcp::McpAction::SetModuleSourcePath(mod_id, part_id, path) = action {
            info!("MCP: SetModuleSourcePath({}, {}, {:?})", mod_id, part_id, path);
            if let Some(module) = app.state.module_manager_mut().get_module_mut(mod_id) {
                if let Some(part) = module.parts.iter_mut().find(|p| p.id == part_id) {
                    let mut path_updated = false;
                    if let vorce_core::module::ModulePartType::Source(
                        vorce_core::module::SourceType::MediaFile {
                            path: ref mut current_path,
                            ..
                        }
                        | vorce_core::module::SourceType::VideoUni {
                            path: ref mut current_path, ..
                        }
                        | vorce_core::module::SourceType::ImageUni {
                            path: ref mut current_path, ..
                        },
                    ) = &mut part.part_type
                    {
                        let new_path_str = path.to_string_lossy().to_string();
                        if *current_path != new_path_str {
                            *current_path = new_path_str;
                            path_updated = true;
                        }
                    }
                    if path_updated {
                        app.state.dirty = true;

                        // Force player reload by removing existing instance
                        // sync_media_players will recreate it with new path
                        if app.media_players.remove(&(mod_id, part_id)).is_some() {
                            info!("Removed player for {} to force reload", part_id);
                        }
                        app.texture_pool.release(&format!("part_{}_{}", mod_id, part_id));
                    }
                }
            }
        }
    }
}
