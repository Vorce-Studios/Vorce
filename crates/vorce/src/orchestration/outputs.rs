//! Window and Output orchestration.

use crate::app::core::app_struct::App;
use anyhow::Result;
use vorce_core::module::OutputType;

#[derive(Debug, Clone)]
struct ProjectorGraphConfig {
    id: u64,
    name: String,
    hide_cursor: bool,
    target_screen: u8,
    output_width: u32,
    output_height: u32,
}

/// Synchronizes output windows with the current module graph configuration.
pub fn sync_output_windows(
    app: &mut App,
    elwt: &winit::event_loop::ActiveEventLoop,
    _ui_needs_sync: bool,
    _graph_dirty: bool,
) -> Result<()> {
    let mut projector_configs = Vec::new();

    for module in app.state.module_manager.modules() {
        for part in &module.parts {
            match &part.part_type {
                vorce_core::module::ModulePartType::Output(OutputType::Projector {
                    id,
                    name,
                    hide_cursor,
                    target_screen,
                    output_width,
                    output_height,
                    ..
                }) => {
                    projector_configs.push(ProjectorGraphConfig {
                        id: *id,
                        name: name.clone(),
                        hide_cursor: *hide_cursor,
                        target_screen: *target_screen,
                        output_width: *output_width,
                        output_height: *output_height,
                    });
                }
                vorce_core::module::ModulePartType::Output(output_type) => {
                    let unsupported_name: Option<(&'static str, String)> = match output_type {
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

    let active_projector_ids: rustc_hash::FxHashSet<u64> =
        projector_configs.iter().map(|config| config.id).collect();

    for config in &projector_configs {
        let resolution = if config.output_width > 0 && config.output_height > 0 {
            (config.output_width, config.output_height)
        } else {
            (1920, 1080)
        };

        let mut output_config =
            if let Some(existing) = app.state.output_manager.get_output(config.id) {
                existing.clone()
            } else {
                vorce_core::OutputConfig::new(
                    config.id,
                    config.name.clone(),
                    vorce_core::CanvasRegion::new(0.0, 0.0, 1.0, 1.0),
                    resolution,
                )
            };

        output_config.name = config.name.clone();
        if config.output_width > 0 && config.output_height > 0 {
            output_config.resolution = (config.output_width, config.output_height);
        }
        output_config.target_screen = config.target_screen;
        output_config.hide_cursor = config.hide_cursor;

        app.state.output_manager_mut().upsert_output(output_config);
    }

    let stale_output_ids: Vec<_> = app
        .state
        .output_manager
        .outputs()
        .iter()
        .filter(|output| output.id != 0 && !active_projector_ids.contains(&output.id))
        .map(|output| output.id)
        .collect();
    for id in stale_output_ids {
        app.state.output_manager_mut().remove_output(id);
    }

    for config in &projector_configs {
        if let Err(err) = app.window_manager.sync_projector_window(
            elwt,
            &app.backend,
            config.id,
            &config.name,
            false,
            config.hide_cursor,
            config.target_screen,
            (config.output_width, config.output_height),
            app.ui_state.user_config.vsync_mode,
        ) {
            tracing::error!(
                "Failed to synchronize projector window '{}' (ID {}): {}",
                config.name,
                config.id,
                err
            );
        }
    }

    let windows_to_remove: Vec<_> = app
        .window_manager
        .window_ids()
        .copied()
        .filter(|window_id| *window_id != 0 && !active_projector_ids.contains(window_id))
        .collect();

    for id in windows_to_remove {
        app.window_manager.remove_window(id);
        tracing::info!("Removed stale output window for ID {}", id);
    }

    Ok(())
}
