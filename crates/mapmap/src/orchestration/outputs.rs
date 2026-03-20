//! Window and Output orchestration.

use crate::app::core::app_struct::App;
use anyhow::Result;
use std::collections::HashSet;
use tracing::info;

/// Synchronizes output windows with the current `OutputManager` configuration.
pub fn sync_output_windows(
    app: &mut App,
    elwt: &winit::event_loop::ActiveEventLoop,
    _ui_needs_sync: bool,
    _graph_dirty: bool,
) -> Result<()> {
    let mut active_window_ids: HashSet<u64> = HashSet::new();

    // 1. Identify all active outputs in the manager
    for output_config in app.state.output_manager.outputs() {
        active_window_ids.insert(output_config.id);

        // Create window if it doesn't exist
        if !app
            .window_manager
            .window_ids()
            .any(|&wid| wid == output_config.id)
        {
            app.window_manager
                .create_output_window(elwt, &app.backend, output_config)?;
        }
    }

    // 2. Remove windows for outputs that no longer exist
    let mut windows_to_remove = Vec::new();
    for &window_id in app.window_manager.window_ids() {
        // ID 0 is the main control window, skip it
        if window_id != 0 && !active_window_ids.contains(&window_id) {
            windows_to_remove.push(window_id);
        }
    }

    for window_id in windows_to_remove {
        app.window_manager.remove_window(window_id);
        info!("Removed output window for output ID {}", window_id);
    }

    Ok(())
}
