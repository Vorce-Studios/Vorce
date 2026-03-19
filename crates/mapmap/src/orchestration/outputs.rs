//! Window and Output orchestration.

use crate::app::core::app_struct::App;
use anyhow::Result;
use mapmap_core::module::OutputType;
use std::collections::HashSet;

/// Synchronizes output windows with the current module graph configuration.
pub fn sync_output_windows(
    app: &mut App,
    elwt: &winit::event_loop::ActiveEventLoop,
    _ui_needs_sync: bool,
    _graph_dirty: bool,
) -> Result<()> {
    let mut active_window_ids: HashSet<u64> = HashSet::new();

    // 1. Identify all active outputs in the graph
    for module in app.state.module_manager.modules() {
        for part in &module.parts {
            if let mapmap_core::module::ModulePartType::Output(OutputType::Projector {
                id,
                name,
                target_screen,
                ..
            }) = &part.part_type
            {
                active_window_ids.insert(*id);

                // Create window if it doesn't exist
                if !app.window_manager.window_ids().any(|&wid| wid == *id) {
                    if let Err(e) = app.window_manager.create_projector_window(
                        elwt,
                        &app.backend,
                        *id,
                        name,
                        false, // Default or fetch from config
                        false, // Default or fetch from config
                        *target_screen,
                        app.ui_state.user_config.vsync_mode,
                    ) {
                        tracing::error!(
                            "Failed to create window for projector '{}' (ID: {}): {}",
                            name,
                            id,
                            e
                        );
                    }
                }
            }
        }
    }

    // 2. Remove stale windows
    let current_window_ids: Vec<u64> = app.window_manager.window_ids().copied().collect();
    for window_id in current_window_ids {
        if window_id != 0 && !active_window_ids.contains(&window_id) {
            app.window_manager.remove_window(window_id);
            tracing::info!("Removed stale window for output ID {}", window_id);
        }
    }

    Ok(())
}
