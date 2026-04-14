//! Window Manager
//!
//! This module handles the creation, tracking, and destruction of all application windows,
//! including the main control window and all output windows. It abstracts away the
//! complexities of managing winit windows and wgpu surfaces.

use anyhow::Result;
use std::collections::HashMap;
use std::sync::Arc;
use tracing::info;
use vorce_core::{OutputId, runtime_paths};
use vorce_render::WgpuBackend;
use vorce_ui::config::VSyncMode;
use winit::{
    event_loop::ActiveEventLoop,
    window::{Fullscreen, Window, WindowAttributes, WindowId},
};

fn vsync_mode_to_present_mode(mode: VSyncMode) -> wgpu::PresentMode {
    match mode {
        VSyncMode::Auto => wgpu::PresentMode::AutoVsync,
        VSyncMode::On => wgpu::PresentMode::Fifo,
        VSyncMode::Off => wgpu::PresentMode::Immediate,
    }
}

fn resolve_target_monitor(
    event_loop: &ActiveEventLoop,
    target_screen: u8,
) -> Option<winit::monitor::MonitorHandle> {
    let monitors: Vec<_> = event_loop.available_monitors().collect();
    if (target_screen as usize) < monitors.len() {
        Some(monitors[target_screen as usize].clone())
    } else if let Some(primary) = event_loop.primary_monitor() {
        info!("Target screen {} not found, using primary monitor", target_screen);
        Some(primary)
    } else {
        None
    }
}

fn fallback_projector_resolution(
    target_monitor: Option<&winit::monitor::MonitorHandle>,
) -> (u32, u32) {
    if let Some(monitor) = target_monitor {
        if let Some(mode) = monitor.video_modes().next() {
            let size = mode.size();
            return (size.width, size.height);
        }
    }

    (1920, 1080)
}

/// Context for a single window, containing the `winit` window, `wgpu` surface,
/// and other related configuration.
pub struct WindowContext {
    /// The `winit` window.
    pub window: Arc<Window>,
    /// The `wgpu` surface associated with the window.
    pub surface: wgpu::Surface<'static>,
    /// The configuration for the `wgpu` surface.
    pub surface_config: wgpu::SurfaceConfiguration,
}

/// Manages all application windows, including the main control window and all output windows.
pub struct WindowManager {
    windows: HashMap<OutputId, WindowContext>,
    window_id_map: HashMap<WindowId, OutputId>,
}

impl Default for WindowManager {
    fn default() -> Self {
        Self::new()
    }
}

impl WindowManager {
    /// Creates a new, empty `WindowManager`.
    pub fn new() -> Self {
        Self { windows: HashMap::new(), window_id_map: HashMap::new() }
    }

    /// Creates the main control window.
    ///
    /// This is the primary window for the application, where the UI is displayed.
    /// It is assigned a reserved `OutputId` of `0`.
    #[allow(dead_code)] // Used for tests and as simple API wrapper
    pub fn create_main_window(
        &mut self,
        event_loop: &ActiveEventLoop,
        backend: &WgpuBackend,
    ) -> Result<OutputId> {
        // Use default size
        self.create_main_window_with_geometry(
            event_loop,
            backend,
            None,
            None,
            None,
            None,
            false,
            VSyncMode::Auto,
        )
    }

    /// Creates the main control window with optional saved geometry.
    #[allow(clippy::too_many_arguments)]
    pub fn create_main_window_with_geometry(
        &mut self,
        event_loop: &ActiveEventLoop,
        backend: &WgpuBackend,
        width: Option<u32>,
        height: Option<u32>,
        x: Option<i32>,
        y: Option<i32>,
        maximized: bool,
        vsync_mode: VSyncMode,
    ) -> Result<OutputId> {
        let default_width = width.unwrap_or(1920);
        let default_height = height.unwrap_or(1080);

        let mut window_attributes = WindowAttributes::default()
            .with_title("Vorce - Main Control")
            .with_window_icon(load_app_icon())
            .with_inner_size(winit::dpi::PhysicalSize::new(default_width, default_height))
            .with_maximized(maximized);

        // Set position if provided
        if let (Some(pos_x), Some(pos_y)) = (x, y) {
            window_attributes =
                window_attributes.with_position(winit::dpi::PhysicalPosition::new(pos_x, pos_y));
        }

        let window = Arc::new(event_loop.create_window(window_attributes)?);

        // Re-apply icon explicitly to be sure
        if let Some(icon) = load_app_icon() {
            window.set_window_icon(Some(icon));
        }

        let window_id = window.id();
        let output_id: OutputId = 0; // Reserved ID for the main window

        let surface = backend.create_surface(window.clone())?;

        // --- EGUI SRGB FIX ---
        // Egui prefers non-sRGB formats because it handles its own gamma correction.
        // We strip the Srgb suffix if present to satisfy egui's preference.
        let mut format = backend.surface_format();
        format = match format {
            wgpu::TextureFormat::Rgba8UnormSrgb => wgpu::TextureFormat::Rgba8Unorm,
            wgpu::TextureFormat::Bgra8UnormSrgb => wgpu::TextureFormat::Bgra8Unorm,
            _ => format,
        };

        let surface_config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            format,
            width: default_width,
            height: default_height,
            present_mode: vsync_mode_to_present_mode(vsync_mode),
            alpha_mode: wgpu::CompositeAlphaMode::Opaque,
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&backend.device, &surface_config);

        let context = WindowContext { window, surface, surface_config };

        self.windows.insert(output_id, context);
        self.window_id_map.insert(window_id, output_id);

        Ok(output_id)
    }

    /// Creates a new projector window from a Module OutputType::Projector.
    ///
    /// If a window for the given `output_id` already exists, this function does nothing.
    #[allow(clippy::too_many_arguments)]
    pub fn create_projector_window(
        &mut self,
        event_loop: &ActiveEventLoop,
        backend: &WgpuBackend,
        output_id: OutputId,
        name: &str,
        fullscreen: bool,
        hide_cursor: bool,
        target_screen: u8,
        resolution: (u32, u32),
        vsync_mode: VSyncMode,
    ) -> Result<()> {
        // Skip if window already exists
        if self.windows.contains_key(&output_id) {
            return Ok(());
        }

        info!(
            "Creating projector window '{}' (ID: {}, Screen: {})",
            name, output_id, target_screen
        );

        let target_monitor = resolve_target_monitor(event_loop, target_screen);
        let (default_width, default_height) = if resolution.0 > 0 && resolution.1 > 0 {
            resolution
        } else {
            fallback_projector_resolution(target_monitor.as_ref())
        };

        let mut window_attributes = WindowAttributes::default()
            .with_title(format!("Vorce - {}", name))
            .with_window_icon(load_app_icon())
            .with_inner_size(winit::dpi::PhysicalSize::new(default_width, default_height));

        // Set fullscreen if requested
        if fullscreen {
            if let Some(monitor) = target_monitor.clone() {
                window_attributes =
                    window_attributes.with_fullscreen(Some(Fullscreen::Borderless(Some(monitor))));
            } else {
                window_attributes =
                    window_attributes.with_fullscreen(Some(Fullscreen::Borderless(None)));
            }
        } else if let Some(monitor) = target_monitor.as_ref() {
            let position = monitor.position();
            window_attributes = window_attributes
                .with_position(winit::dpi::PhysicalPosition::new(position.x, position.y));
        }

        // Build the window
        let window = Arc::new(event_loop.create_window(window_attributes)?);

        // Re-apply icon explicitly to be sure
        if let Some(icon) = load_app_icon() {
            window.set_window_icon(Some(icon));
        }

        // Hide cursor if requested
        window.set_cursor_visible(!hide_cursor);

        let window_id_winit = window.id();

        // Create surface for this output window
        let surface = backend.create_surface(window.clone())?;
        let actual_size = window.inner_size();

        let surface_config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            format: backend.surface_format(),
            width: actual_size.width.max(1),
            height: actual_size.height.max(1),
            present_mode: vsync_mode_to_present_mode(vsync_mode), // VSync for synchronized output
            alpha_mode: wgpu::CompositeAlphaMode::Opaque,
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };

        surface.configure(&backend.device, &surface_config);

        let window_context = WindowContext { window, surface, surface_config };

        self.windows.insert(output_id, window_context);
        self.window_id_map.insert(window_id_winit, output_id);

        info!("Created projector window '{}' at {}x{}", name, default_width, default_height);

        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub fn sync_projector_window(
        &mut self,
        event_loop: &ActiveEventLoop,
        backend: &WgpuBackend,
        output_id: OutputId,
        name: &str,
        fullscreen: bool,
        hide_cursor: bool,
        target_screen: u8,
        resolution: (u32, u32),
        vsync_mode: VSyncMode,
    ) -> Result<()> {
        if !self.windows.contains_key(&output_id) {
            return self.create_projector_window(
                event_loop,
                backend,
                output_id,
                name,
                fullscreen,
                hide_cursor,
                target_screen,
                resolution,
                vsync_mode,
            );
        }

        let target_monitor = resolve_target_monitor(event_loop, target_screen);
        let context =
            self.windows.get_mut(&output_id).expect("checked window existence before sync");

        context.window.set_title(&format!("Vorce - {}", name));
        context.window.set_cursor_visible(!hide_cursor);

        if fullscreen {
            context.window.set_fullscreen(Some(Fullscreen::Borderless(target_monitor.clone())));
        } else {
            context.window.set_fullscreen(None);
            if let Some(monitor) = target_monitor {
                let position = monitor.position();
                context
                    .window
                    .set_outer_position(winit::dpi::PhysicalPosition::new(position.x, position.y));
            }
        }

        if resolution.0 > 0 && resolution.1 > 0 {
            let _ = context
                .window
                .request_inner_size(winit::dpi::PhysicalSize::new(resolution.0, resolution.1));
        }

        let actual_size = context.window.inner_size();
        let present_mode = vsync_mode_to_present_mode(vsync_mode);
        let width = actual_size.width.max(1);
        let height = actual_size.height.max(1);

        if context.surface_config.width != width
            || context.surface_config.height != height
            || context.surface_config.present_mode != present_mode
        {
            context.surface_config.width = width;
            context.surface_config.height = height;
            context.surface_config.present_mode = present_mode;
            context.surface.configure(&backend.device, &context.surface_config);
        }

        Ok(())
    }

    /// Removes a window by its `OutputId`.
    pub fn remove_window(&mut self, output_id: OutputId) -> Option<WindowContext> {
        if let Some(context) = self.windows.remove(&output_id) {
            self.window_id_map.remove(&context.window.id());
            Some(context)
        } else {
            None
        }
    }

    /// Returns a reference to a `WindowContext` by its `OutputId`.
    pub fn get(&self, output_id: OutputId) -> Option<&WindowContext> {
        self.windows.get(&output_id)
    }

    /// Returns a mutable reference to a `WindowContext` by its `OutputId`.
    pub fn get_mut(&mut self, output_id: OutputId) -> Option<&mut WindowContext> {
        self.windows.get_mut(&output_id)
    }

    /// Returns an iterator over all `OutputId`s.
    pub fn window_ids(&self) -> impl Iterator<Item = &OutputId> {
        self.windows.keys()
    }

    /// Returns an iterator over all `WindowContext`s.
    pub fn iter(&self) -> impl Iterator<Item = &WindowContext> {
        self.windows.values()
    }

    /// Returns the `OutputId` for a given `winit` `WindowId`.
    pub fn get_output_id_from_window_id(&self, window_id: WindowId) -> Option<OutputId> {
        self.window_id_map.get(&window_id).copied()
    }

    /// Requests a redraw for all managed windows.
    ///
    /// This avoids the need for the caller to collect window IDs and iterate manually,
    /// preventing unnecessary allocations in the hot loop.
    #[allow(dead_code)] // Helper for cleaner main loop
    pub fn request_redraw_all(&self) {
        for context in self.windows.values() {
            context.window.request_redraw();
        }
    }

    /// Updates the VSync mode for all managed windows.
    pub fn update_vsync_mode(&mut self, backend: &WgpuBackend, mode: VSyncMode) {
        let present_mode = vsync_mode_to_present_mode(mode);
        for context in self.windows.values_mut() {
            context.surface_config.present_mode = present_mode;
            context.surface.configure(&backend.device, &context.surface_config);
        }
    }
}

/// Helper function to load the application icon.
fn load_app_icon() -> Option<winit::window::Icon> {
    let search_paths = [
        runtime_paths::existing_resource_path("app_icons/Vorce_Logo_HQ-Full-M.png"),
        runtime_paths::existing_resource_path("app_icons/vorce.png"),
    ];

    for path in search_paths.into_iter().flatten() {
        match image::open(&path) {
            Ok(img) => {
                let rgba = img.to_rgba8();
                let (width, height) = rgba.dimensions();
                tracing::info!("Found icon at {:?} ({}x{})", path, width, height);
                match winit::window::Icon::from_rgba(rgba.into_raw(), width, height) {
                    Ok(icon) => {
                        tracing::info!("Successfully created winit icon from {:?}", path);
                        return Some(icon);
                    }
                    Err(e) => {
                        tracing::warn!("Failed to create winit icon from {:?}: {}", path, e);
                    }
                }
            }
            Err(e) => {
                tracing::warn!("Failed to open icon {:?}: {}", path, e);
            }
        }
    }
    None
}
