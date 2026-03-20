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

    // 1. Reconcile graph Projector nodes into OutputManager
    // First, collect the required updates to avoid borrowing `app.state` mutably while iterating over it
    let mut projector_configs = Vec::new();

    for module in app.state.module_manager.modules() {
        for part in &module.parts {
            if let mapmap_core::module::ModulePartType::Output(OutputType::Projector {
                id,
                name,
                output_width,
                output_height,
                ..
            }) = &part.part_type
            {
                active_window_ids.insert(*id);
                projector_configs.push((*id, name.clone(), *output_width, *output_height));
            }
        }
    }

    for (id, name, output_width, output_height) in projector_configs {
        let mut config = if let Some(existing) = app.state.output_manager.get_output(id) {
            existing.clone()
        } else {
            mapmap_core::OutputConfig::new(
                id,
                name.clone(),
                mapmap_core::CanvasRegion::new(0.0, 0.0, 1.0, 1.0),
                (output_width, output_height),
            )
        };

        config.name = name;
        if output_width > 0 && output_height > 0 {
            config.resolution = (output_width, output_height);
        }

        app.state.output_manager_mut().upsert_output(config);
    }

    // 2. WindowManager strictly follows OutputManager configuration
    for output_config in app.state.output_manager.outputs() {
        if active_window_ids.contains(&output_config.id) {
            if !app.window_manager.window_ids().any(|&wid| wid == output_config.id) {
                app.window_manager.create_output_window(
                    elwt,
                    &app.backend,
                    output_config,
                )?;
            }
        }
    }

    // 3. Delete stale windows deterministically
    let mut windows_to_remove = Vec::new();
    for &window_id in app.window_manager.window_ids() {
        if window_id != 0 && !active_window_ids.contains(&window_id) {
            windows_to_remove.push(window_id);
        }
    }

    for id in windows_to_remove {
        app.window_manager.remove_window(id);
        tracing::info!("Removed stale output window for ID {}", id);
    }

    Ok(())
}
