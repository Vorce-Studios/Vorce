//! Video player and media orchestration.

use crate::app::core::app_struct::App;
use crate::orchestration::media_pipeline::{ActiveMediaPipeline, WgpuFrameUploader};
use mapmap_core::module::{ModulePartType, SourceType};
use mapmap_media::pipeline::FramePipeline;
use mapmap_media::player::{PlaybackCommand, PlaybackState};
use tracing::{error, info};

/// Synchronize media players with active source modules
pub fn sync_media_players(app: &mut App) {
    let mut active_sources = std::collections::HashSet::new();

    // Collect active media configurations to avoid borrowing app.state while mutating app.media_players
    let mut media_configs = Vec::new();

    for module in app.state.module_manager.modules() {
        for part in &module.parts {
            if let ModulePartType::Source(source_type) = &part.part_type {
                let path_result = match source_type {
                    SourceType::MediaFile { path, .. } => Some(path.clone()),
                    SourceType::VideoUni { path, .. } => Some(path.clone()),
                    SourceType::ImageUni { path, .. } => Some(path.clone()),
                    SourceType::VideoMulti { shared_id, .. }
                    | SourceType::ImageMulti { shared_id, .. } => {
                        // Look up path in shared media
                        app.state
                            .module_manager
                            .shared_media
                            .get(shared_id)
                            .map(|item| item.path.clone())
                    }
                    _ => None,
                };

                if let Some(path) = path_result {
                    if !path.is_empty() {
                        media_configs.push((module.id, part.id, path));
                    }
                }
            }
        }
    }

    for (mod_id, part_id, path) in media_configs {
        let key = (mod_id, part_id);
        active_sources.insert(key);
        let texture_name = format!("part_{}_{}", mod_id, part_id);

        // Check if we need to create or update player
        let needs_create = if let Some(pipeline) = app.media_players.get(&key) {
             pipeline.source_path != path
        } else {
            true
        };

        if needs_create {
            if app.media_players.contains_key(&key) {
                info!(
                    "Path changed for source {}:{} -> loading {}",
                    mod_id, part_id, path
                );
                // Remove old player
                app.media_players.remove(&key);
            }

            // Create new player
            match mapmap_media::open_path(&path) {
                Ok(player) => {
                    info!(
                        "Created media player for module={} part={} path='{}'",
                        mod_id, part_id, path
                    );

                    // Extract control channels and info before moving player
                    let command_tx = player.command_sender();
                    let status_rx = player.status_receiver();
                    let duration = player.duration();

                    // Initial Play command
                    let _ = command_tx.send(PlaybackCommand::Play);

                    // Create pipeline
                    let mut pipeline = FramePipeline::new();

                    // Setup Uploader
                    let uploader = WgpuFrameUploader::new(
                        app.backend.queue.clone(),
                        app.texture_pool.clone(),
                        texture_name.clone(),
                    );
                    pipeline.set_uploader(Box::new(uploader));

                    // Start threads
                    pipeline.start_decode_thread(player);
                    pipeline.start_upload_thread();

                    let active_pipeline = ActiveMediaPipeline::new(
                        pipeline,
                        command_tx,
                        status_rx,
                        texture_name,
                        duration,
                        path.clone()
                    );

                    app.media_players.insert(key, active_pipeline);
                }
                Err(e) => {
                    error!(
                        "Failed to create video player for source {}:{} : {}",
                        mod_id, part_id, e
                    );
                }
            }
        }
    }

    // Cleanup removed players
    app.media_players
        .retain(|key, _| active_sources.contains(key));
}

/// Update all media players and sync stats to UI
#[allow(clippy::manual_is_multiple_of)]
pub fn update_media_players(app: &mut App, _dt: f32) {
    let ui_state = &mut app.ui_state;

    for ((mod_id, part_id), pipeline) in &mut app.media_players {
        // Update state from status channel
        pipeline.update_state();

        // Get stats
        let stats = pipeline.pipeline.stats();

        // Sync player info to UI for timeline display
        if let Some(active_id) = ui_state.module_canvas.active_module_id {
            if *mod_id == active_id {
                ui_state.module_canvas.player_info.insert(
                    *part_id,
                    mapmap_ui::types::MediaPlayerInfo {
                        current_time: stats.last_pts_secs,
                        duration: pipeline.duration.as_secs_f64(),
                        is_playing: matches!(pipeline.current_state, PlaybackState::Playing),
                    },
                );
            }
        }
    }
}
