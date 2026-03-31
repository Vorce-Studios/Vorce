//! Window and Output orchestration.

use crate::app::core::app_struct::App;
use anyhow::Result;
use std::collections::HashSet;
use vorce_core::module::OutputType;

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
            match &part.part_type {
                vorce_core::module::ModulePartType::Output(OutputType::Projector {
                    id,
                    name,
                    output_width,
                    output_height,
                    target_screen,
                    hide_cursor,
                    ..
                }) => {
                    active_window_ids.insert(*id);
                    projector_configs.push((
                        *id,
                        name.clone(),
                        *output_width,
                        *output_height,
                        *target_screen,
                        *hide_cursor,
                    ));
                }
                vorce_core::module::ModulePartType::Output(output_type) => {
                    let unsupported_name = match output_type {
                        OutputType::NdiOutput { name } => Some(("NDI Output", name.clone())),
                        #[cfg(target_os = "windows")]
                        OutputType::Spout { name } => Some(("Spout Output", name.clone())),
                        _ => None,
                    };

                    if let Some((type_name, node_name)) = unsupported_name {
                        let now = std::time::Instant::now();
                        let log_key = format!("{}_unsupported_{}", type_name, node_name);
                        let should_log =
                            if let Some(last_log) = app.video_diagnostic_log_times.get(&log_key) {
                                now.duration_since(*last_log).as_secs_f32() > 5.0
                            } else {
                                true
                            };
                        if should_log {
                            tracing::warn!(
                                "{} '{}' is currently unsupported/experimental and will not broadcast.",
                                type_name,
                                node_name
                            );
                            app.video_diagnostic_log_times.insert(log_key, now);
                        }
                    }
                }
                _ => {}
            }
        }
    }

    for (id, name, output_width, output_height, target_screen, hide_cursor) in projector_configs {
        let mut config = if let Some(existing) = app.state.output_manager.get_output(id) {
            existing.clone()
        } else {
            vorce_core::OutputConfig::new(
                id,
                name.clone(),
                vorce_core::CanvasRegion::new(0.0, 0.0, 1.0, 1.0),
                (output_width, output_height),
            )
        };

        config.name = name;
        if output_width > 0 && output_height > 0 {
            config.resolution = (output_width, output_height);
        }
        config.target_screen = target_screen;
        config.hide_cursor = hide_cursor;

        app.state.output_manager_mut().upsert_output(config);
    }

    // 2. WindowManager strictly follows OutputManager configuration
    for output_config in app.state.output_manager.outputs() {
        if active_window_ids.contains(&output_config.id)
            && !app
                .window_manager
                .window_ids()
                .any(|&wid| wid == output_config.id)
        {
            app.window_manager
                .create_output_window(elwt, &app.backend, output_config)?;
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
