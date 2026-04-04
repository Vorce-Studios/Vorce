//! Vorce - Open source VJ projection mapping software.
//!
//! This is the main application crate for Vorce.
//! VERSION: 2026-03-19-VISUAL-TEST-READY

#![warn(missing_docs)]

pub mod app;
/// UI components.
/// CLI arguments parsing and types.
pub mod cli;
mod media_manager_ui;
/// Orchestration and node evaluation logic.
pub mod orchestration;
/// Player modes.
pub mod player;
/// UI components.
pub mod ui;
mod window_manager;

use anyhow::{Context, Result};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use vorce_core::OutputId;
use vorce_media::PlaybackCommand;
use vorce_ui::types::MediaPlaybackCommand;

use tracing::{error, info};
use tracing_subscriber::prelude::*;

use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Fullscreen, WindowId};

use crate::app::core::app_struct::{App, InitializationConfig};

use crate::cli::{CliArgs, Mode};
use clap::Parser;

struct VorceApp {
    app: Option<App>,
    is_automation: bool,
    fixture: Option<String>,
    exit_after_frames: Option<u64>,
    screenshot_dir: Option<String>,
    initial_user_config: vorce_ui::config::UserConfig,
    disable_startup_animation: bool,
startup_failure: Option<String>,
pending_main_window_state_persist_at: Option<Instant>,
}
impl VorceApp {
    fn schedule_main_window_state_persist(&mut self) {
        self.pending_main_window_state_persist_at =
            Some(Instant::now() + Duration::from_millis(250));
    }

    fn persist_main_window_state_if_due(&mut self, force: bool) {
        let Some(app) = &mut self.app else {
            return;
        };

        let should_persist = force
            || self
                .pending_main_window_state_persist_at
                .is_some_and(|deadline| Instant::now() >= deadline);
        if !should_persist {
            return;
        }

        self.pending_main_window_state_persist_at = None;
        if let Err(err) = app.persist_main_window_state() {
            error!("Failed to persist main window state: {err:#}");
        }
    }
>>>>>>> main
}

impl ApplicationHandler for VorceApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.app.is_none() {
            info!("Initializing Vorce...");

            let config = if self.is_automation {
                InitializationConfig::automation()
            } else {
                InitializationConfig::default()
            };

            let mut app = match pollster::block_on(App::new(
                event_loop,
                config,
                self.initial_user_config.clone(),
            )) {
                Ok(app) => app,
                Err(err) => {
                    error!("Failed to initialize application: {err:#}");
                    event_loop.exit();
                    return;
                }
            };

            if self.disable_startup_animation {
                app.ui_state.user_config.startup_animation_enabled = false;
            }

            // Automation mode: load fixture if specified
            if self.is_automation {
                if let Some(fixture_path) = &self.fixture {
                    info!("Automation mode: Loading fixture {}", fixture_path);
                    match vorce_io::load_project(std::path::Path::new(fixture_path)) {
                        Ok(loaded_state) => {
                            app.state = loaded_state;
                            app.state.dirty = true;
                            info!("Fixture loaded successfully.");
                        }
                        Err(e) => {
                            error!("Automation mode: Failed to load fixture: {}", e);
                            event_loop.exit();
                        }
                    }
                }
            }

            self.app = Some(app);
        }
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        window_id: WindowId,
        event: WindowEvent,
    ) {
        let mut should_persist_main_window_state = false;
        let mut close_requested_on_main_window = false;

        if let Some(app) = &mut self.app {
            let is_main_window = app
                .window_manager
                .get(0)
                .map(|main_window| main_window.window.id() == window_id)
                .unwrap_or(false);
            should_persist_main_window_state = is_main_window
                && matches!(
                    &event,
                    WindowEvent::Moved(_)
                        | WindowEvent::Resized(_)
                        | WindowEvent::ScaleFactorChanged { .. }
                        | WindowEvent::CloseRequested
                );
            close_requested_on_main_window =
                is_main_window && matches!(&event, WindowEvent::CloseRequested);
            let should_request_main_redraw = is_main_window
                && matches!(
                    &event,
                    WindowEvent::CursorMoved { .. }
                        | WindowEvent::CursorEntered { .. }
                        | WindowEvent::CursorLeft { .. }
                        | WindowEvent::MouseInput { .. }
                        | WindowEvent::MouseWheel { .. }
                        | WindowEvent::KeyboardInput { .. }
                        | WindowEvent::Ime(_)
                        | WindowEvent::Focused(_)
                        | WindowEvent::ModifiersChanged(_)
                        | WindowEvent::Touch(_)
                );

            if let Err(err) = app.handle_event(
                winit::event::Event::WindowEvent { window_id, event },
                event_loop,
            ) {
                error!("Unhandled window event error for {:?}: {err:#}", window_id);
            }

            if should_request_main_redraw {
                if let Some(main_window) = app.window_manager.get(0) {
                    main_window.window.request_redraw();
                }
            }
        }

        if should_persist_main_window_state {
            if close_requested_on_main_window {
                self.persist_main_window_state_if_due(true);
            } else {
                self.schedule_main_window_state_persist();
            }
        }
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(app) = &mut self.app {
            if let Err(err) = app.handle_event(winit::event::Event::AboutToWait, event_loop) {
                error!("Unhandled about-to-wait error: {err:#}");
            }

            if self.is_automation {
                if let Some(exit_frames) = self.exit_after_frames {
                    if app.frame_counter >= exit_frames {
                        if let Some(dir) = &self.screenshot_dir {
                            let path = std::path::PathBuf::from(dir);
                            std::fs::create_dir_all(&path).unwrap_or_else(|e| {
                                error!("Failed to create screenshot directory: {}", e);
                            });

                            let file_path =
                                path.join(format!("automation_frame_{}.png", exit_frames));
                            info!("Automation mode: Saving screenshot to {:?}", file_path);

                            // Trigger capture using the shared utility
                            if let Some(main_window_context) = app.window_manager.get(0) {
                                let format = main_window_context.surface_config.format;
                                let width = main_window_context.surface_config.width;
                                let height = main_window_context.surface_config.height;

                                let mut encoder = app.backend.device.create_command_encoder(
                                    &wgpu::CommandEncoderDescriptor {
                                        label: Some("Automation Screenshot Encoder"),
                                    },
                                );

                                if let Some(texture) = app.texture_pool.get_texture("composite") {
                                    let (buffer, padded_bytes_per_row) =
                                        vorce_render::capture::queue_readback_copy(
                                            &app.backend.device,
                                            &mut encoder,
                                            &texture,
                                            width,
                                            height,
                                        );

                                    app.backend.queue.submit(std::iter::once(encoder.finish()));

                                    if let Err(e) = vorce_render::capture::save_readback_buffer(
                                        &app.backend.device,
                                        buffer,
                                        width,
                                        height,
                                        padded_bytes_per_row,
                                        format,
                                        &file_path,
                                    ) {
                                        error!("Failed to save automation screenshot: {}", e);
                                    }
                                } else {
                                    error!(
                                        "Could not find composite texture for automation capture"
                                    );
                                }
                            } else {
                                error!("Automation mode: Main window context not found for screenshot.");
                            }
                        }

                        info!(
                            "Automation mode: Reached frame limit ({}). Exiting.",
                            exit_frames
                        );
                        event_loop.exit();
                    }
                }
            }
        }

        self.persist_main_window_state_if_due(false);
    }
}

impl App {
    /// Persists the current main-window geometry and display state into the user config.
    pub fn persist_main_window_state(&mut self) -> Result<bool> {
        let Some(main_window) = self.window_manager.get(0) else {
            return Ok(false);
        };

        let fullscreen = main_window.window.fullscreen().is_some();
        let maximized = main_window.window.is_maximized();
        let size = main_window.window.inner_size();
        let outer_position = main_window.window.outer_position().ok();

        let mut changed = false;
        let user_config = &mut self.ui_state.user_config;

        if user_config.window_fullscreen != fullscreen {
            user_config.window_fullscreen = fullscreen;
            changed = true;
        }

        if user_config.window_maximized != maximized {
            user_config.window_maximized = maximized;
            changed = true;
        }

        if !fullscreen {
            let width = Some(size.width.max(1));
            let height = Some(size.height.max(1));

            if user_config.window_width != width {
                user_config.window_width = width;
                changed = true;
            }
            if user_config.window_height != height {
                user_config.window_height = height;
                changed = true;
            }

            if let Some(position) = outer_position {
                let x = Some(position.x);
                let y = Some(position.y);

                if user_config.window_x != x {
                    user_config.window_x = x;
                    changed = true;
                }
                if user_config.window_y != y {
                    user_config.window_y = y;
                    changed = true;
                }
            }
        }

        if changed {
            self.ui_state.user_config.save()?;
        }

        Ok(changed)
    }

    /// Applies fullscreen to the main window and immediately persists the resulting state.
    pub fn set_main_window_fullscreen(&mut self, fullscreen: bool) -> Result<()> {
        let Some(main_window) = self.window_manager.get(0) else {
            anyhow::bail!("Main window context not found");
        };

        main_window.window.set_fullscreen(
            fullscreen.then(|| Fullscreen::Borderless(main_window.window.current_monitor())),
        );
        main_window.window.request_redraw();
        self.persist_main_window_state()?;
        Ok(())
    }

    /// Handles a window event.
    pub fn handle_event(
        &mut self,
        event: winit::event::Event<()>,
        elwt: &winit::event_loop::ActiveEventLoop,
    ) -> Result<()> {
        if self.exit_requested {
            elwt.exit();
        }

        match &event {
            winit::event::Event::WindowEvent { event, window_id } => {
                if let Some(main_window) = self.window_manager.get(0) {
                    if *window_id == main_window.window.id() {
                        let _ = self.egui_state.on_window_event(&main_window.window, event);
                    }
                }

                let output_id = self
                    .window_manager
                    .get_output_id_from_window_id(*window_id)
                    .unwrap_or(0);

                match event {
                    WindowEvent::CloseRequested => {
                        if output_id == 0 {
                            elwt.exit();
                        }
                    }
                    WindowEvent::Resized(size) => {
                        let new_size =
                            if let Some(window_context) = self.window_manager.get_mut(output_id) {
                                if size.width > 0 && size.height > 0 {
                                    window_context.surface_config.width = size.width;
                                    window_context.surface_config.height = size.height;
                                    window_context.surface.configure(
                                        &self.backend.device,
                                        &window_context.surface_config,
                                    );
                                    Some((
                                        size.width,
                                        size.height,
                                        window_context.surface_config.format,
                                    ))
                                } else {
                                    None
                                }
                            } else {
                                None
                            };
                        // Recreate dummy texture for the new size
                        match new_size {
                            Some((width, height, format)) => {
                                self.create_dummy_texture(width, height, format);
                            }
                            None => {
                                tracing::warn!(
                                    "Resize event received but no valid new size was determined."
                                );
                            }
                        }
                    }
                    WindowEvent::RedrawRequested => {
                        if let Err(e) = self.render(output_id) {
                            error!("Render error on output {}: {}", output_id, e);
                        }
                    }
                    _ => (),
                }
            }
            winit::event::Event::AboutToWait => {
                // Logic update at a fixed rate (e.g. 60Hz)
                let now = std::time::Instant::now();
                let dt = now.duration_since(self.last_update).as_secs_f32();

                // Cap dt to avoid huge jumps
                let dt = dt.min(0.1);

                let has_modules = !self.state.module_manager.modules().is_empty();
                let has_projector_outputs =
                    self.state.module_manager.modules().iter().any(|module| {
                        module.parts.iter().any(|part| {
                            matches!(
                                part.part_type,
                                vorce_core::module::ModulePartType::Output(
                                    vorce_core::module::OutputType::Projector { .. }
                                )
                            )
                        })
                    });
                let is_playing = self.state.effect_animator.is_playing();
                let configured_fps = self.ui_state.target_fps.max(1.0);
                let tick_fps = if !has_modules {
                    10.0
                } else if is_playing {
                    configured_fps
                } else {
                    // Editing/idle mode with modules loaded: lower tick rate to reduce CPU.
                    configured_fps.min(30.0)
                };
                let target_interval = 1.0 / tick_fps;

                if dt >= target_interval {
                    if let Err(e) = self.update(elwt, dt) {
                        error!("Update error: {}", e);
                    }
                    self.last_update = now;

                    if has_modules {
                        if is_playing || has_projector_outputs {
                            self.window_manager.request_redraw_all();
                        } else if let Some(main_window) = self.window_manager.get(0) {
                            main_window.window.request_redraw();
                        }
                    } else if let Some(main_window) = self.window_manager.get(0) {
                        // Keep the empty-project UI responsive: without a redraw here,
                        // the first frame can remain frozen and user input appears dead.
                        main_window.window.request_redraw();
                    }

                    elwt.set_control_flow(winit::event_loop::ControlFlow::WaitUntil(
                        self.last_update + std::time::Duration::from_secs_f32(target_interval),
                    ));
                } else {
                    let wait_until =
                        self.last_update + std::time::Duration::from_secs_f32(target_interval);
                    elwt.set_control_flow(winit::event_loop::ControlFlow::WaitUntil(wait_until));
                }
            }
            _ => (),
        }

        Ok(())
    }

    /// Global render update
    pub fn render(&mut self, output_id: OutputId) -> Result<()> {
        crate::app::loops::render::render(self, output_id)
    }

    /// Global logic update
    pub fn update(&mut self, elwt: &winit::event_loop::ActiveEventLoop, dt: f32) -> Result<()> {
        crate::app::loops::logic::update(self, elwt, dt)?;

        let commands = self.ui_state.module_canvas.take_playback_commands();
        for (part_id, cmd) in commands {
            let mut target_module_id = None;
            for module in self.state.module_manager.modules() {
                if module.parts.iter().any(|p| p.id == part_id) {
                    target_module_id = Some(module.id);
                    break;
                }
            }

            if let Some(mod_id) = target_module_id {
                let player_key = (mod_id, part_id);

                if cmd == MediaPlaybackCommand::Reload {
                    if self.media_players.remove(&player_key).is_some() {
                        info!(
                            "Removed old media player for part_id={} for reload",
                            part_id
                        );
                    }
                    self.texture_pool
                        .release(&format!("part_{}_{}", mod_id, part_id));
                    crate::orchestration::media::sync_media_players(self);
                    continue;
                }

                if !self.media_players.contains_key(&player_key) {
                    crate::orchestration::media::sync_media_players(self);
                }

                if let Some(player) = self.media_players.get_mut(&player_key) {
                    match cmd {
                        MediaPlaybackCommand::Play => {
                            let _ = player.command_tx.send(PlaybackCommand::Play);
                        }
                        MediaPlaybackCommand::Pause => {
                            let _ = player.command_tx.send(PlaybackCommand::Pause);
                        }
                        MediaPlaybackCommand::Stop => {
                            let _ = player.command_tx.send(PlaybackCommand::Stop);
                        }
                        MediaPlaybackCommand::Reload => unreachable!(),
                        MediaPlaybackCommand::SetSpeed(speed) => {
                            let _ = player.command_tx.send(PlaybackCommand::SetSpeed(speed));
                        }
                        MediaPlaybackCommand::SetLoop(enabled) => {
                            let mode = if enabled {
                                vorce_media::LoopMode::Loop
                            } else {
                                vorce_media::LoopMode::PlayOnce
                            };
                            let _ = player.command_tx.send(PlaybackCommand::SetLoopMode(mode));
                        }
                        MediaPlaybackCommand::Seek(position) => {
                            let _ = player.command_tx.send(PlaybackCommand::Seek(
                                std::time::Duration::from_secs_f64(position),
                            ));
                        }
                        MediaPlaybackCommand::SetReverse(reverse) => {
                            info!(
                                "Setting reverse playback to {} for part_id={} (NOT IMPLEMENTED)",
                                reverse, part_id
                            );
                        }
                    }
                }
            }
        }

        Ok(())
    }
}

fn main() -> Result<()> {
    // Set up panic hook EARLY to capture startup crashes BEFORE logging is initialized.
    // This hook writes to both stderr AND a fallback log file for maximum debuggability.
    std::panic::set_hook(Box::new(|panic_info| {
        let location = panic_info
            .location()
            .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
            .unwrap_or_else(|| "unknown".to_string());
        let payload = panic_info.payload();
        let message = if let Some(s) = payload.downcast_ref::<&str>() {
            *s
        } else if let Some(s) = payload.downcast_ref::<String>() {
            s.as_str()
        } else {
            "Box<Any>"
        };

        let panic_msg = format!("APPLICATION PANIC at {}: {}", location, message);

        // Always write to stderr for immediate visibility
        eprintln!("{}", panic_msg);

        // Also attempt to write to fallback log file (even before logging is set up)
        if let Ok(mut path) = std::env::current_dir() {
            path.push("logs");
            path.push("vorce-panic-fallback.log");
            if let Some(parent) = path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let timestamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let log_entry = format!("[{}] FATAL: {}\n", timestamp, panic_msg);
            let _ = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&path)
                .and_then(|mut f| std::io::Write::write_all(&mut f, log_entry.as_bytes()));
        }
    }));

    let args = CliArgs::parse();
    let (initial_user_config, initial_user_config_report) =
        vorce_ui::config::UserConfig::load_with_report();
    let configured_log_level = match initial_user_config.log_level {
        vorce_ui::config::AppLogLevel::Info => tracing::Level::INFO,
        vorce_ui::config::AppLogLevel::Debug => tracing::Level::DEBUG,
    };

    let file_appender = tracing_appender::rolling::daily("logs", "vorce.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

    let env_filter = tracing_subscriber::EnvFilter::from_default_env()
        .add_directive(configured_log_level.into())
        .add_directive("wgpu_core=warn".parse().unwrap())
        .add_directive("wgpu_hal=warn".parse().unwrap())
        .add_directive("naga=warn".parse().unwrap())
        .add_directive("winit=info".parse().unwrap());

    let console_layer = tracing_subscriber::fmt::layer()
        .with_ansi(true)
        .with_target(true)
        .with_thread_ids(false)
        .with_thread_names(false)
        .with_writer(std::io::stdout);

    let file_layer = tracing_subscriber::fmt::layer()
        .with_ansi(false)
        .with_target(true)
        .with_writer(non_blocking);

    tracing_subscriber::registry()
        .with(env_filter)
        .with(console_layer)
        .with(file_layer)
        .init();

    initial_user_config_report.emit_logs();
    info!("Starting Vorce in {:?} mode...", args.mode);

    match args.mode {
        Mode::Editor => run_editor(initial_user_config.clone(), args.no_splash)?,
        Mode::Automation => run_automation(&args, initial_user_config.clone())?,
        Mode::PlayerNdi => run_player_ndi(&args)?,
        Mode::PlayerDist => run_player_dist(&args)?,
        Mode::PlayerLegacy => run_player_legacy(&args)?,
        Mode::PlayerPi => run_player_pi(&args)?,
    }

    Ok(())
}

fn run_editor(
    initial_user_config: vorce_ui::config::UserConfig,
    disable_startup_animation: bool,
) -> Result<()> {
    info!("Starting Editor mode...");
    let event_loop = EventLoop::new()?;
    let mut app_handler = VorceApp {
        app: None,
        is_automation: false,
        fixture: None,
        exit_after_frames: None,
        screenshot_dir: None,
        initial_user_config,
        disable_startup_animation,
        startup_failure: None,
        pending_main_window_state_persist_at: None,
    };
    event_loop.run_app(&mut app_handler)?;
    Ok(())
}

fn run_automation(args: &CliArgs, initial_user_config: vorce_ui::config::UserConfig) -> Result<()> {
    info!("Starting Automation mode...");
    let event_loop = EventLoop::new()?;
    let mut app_handler = VorceApp {
        app: None,
        is_automation: true,
        fixture: args.fixture.clone(),
        exit_after_frames: args.exit_after_frames,
        screenshot_dir: args.screenshot_dir.clone(),
        initial_user_config,
        disable_startup_animation: true,
        startup_failure: None,
        pending_main_window_state_persist_at: None,
    };
    event_loop.run_app(&mut app_handler)?;
    Ok(())
}

fn run_player_ndi(args: &CliArgs) -> Result<()> {
    crate::player::ndi_player::run(args)
}
fn run_player_dist(_args: &CliArgs) -> Result<()> {
    info!("Starting Distributed Player mode...");
    Ok(())
}
fn run_player_legacy(_args: &CliArgs) -> Result<()> {
    info!("Starting Legacy RTSP/H.264 Player mode...");
    Ok(())
}
fn run_player_pi(_args: &CliArgs) -> Result<()> {
    info!("Starting Raspberry Pi Player mode...");
    Ok(())
}
