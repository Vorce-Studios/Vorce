use std::sync::Arc;

/// Render targets setup
pub struct RenderTargets {
    /// Use edge blend
    pub use_edge_blend: bool,
    /// Use color calibration
    pub use_color_calib: bool,
    /// Needs post processing
    pub needs_post_processing: bool,
    /// Mesh target view reference
    pub mesh_target_view_ref: Option<Arc<wgpu::TextureView>>,
    /// Color target view reference
    pub color_target_view_ref: Option<Arc<wgpu::TextureView>>,
    /// Target width
    pub target_width: u32,
    /// Target height
    pub target_height: u32,
    /// Output config option
    pub output_config_opt: Option<vorce_core::output::OutputConfig>,
}

/// Setup render targets
pub fn setup_render_targets(
    output_manager: &vorce_core::output::OutputManager,
    texture_pool: &vorce_render::TexturePool,
    surface_format: wgpu::TextureFormat,
    real_output_id: u64,
    output_id: u64,
    has_edge_blend_renderer: bool,
    has_color_calibration_renderer: bool,
) -> RenderTargets {
    let output_config_opt = output_manager.get_output(real_output_id).cloned();
    let use_edge_blend = output_config_opt
        .as_ref()
        .map(|cfg| {
            cfg.edge_blend.left.enabled
                || cfg.edge_blend.right.enabled
                || cfg.edge_blend.top.enabled
                || cfg.edge_blend.bottom.enabled
        })
        .unwrap_or(false)
        && has_edge_blend_renderer;

    let use_color_calib = output_config_opt
        .as_ref()
        .map(|cfg| cfg.color_calibration != vorce_core::ColorCalibration::default())
        .unwrap_or(false)
        && has_color_calibration_renderer;

    let needs_post_processing = use_edge_blend || use_color_calib;

    let post_a_tex_name = format!("output_{}_post_a", output_id);
    let post_b_tex_name = format!("output_{}_post_b", output_id);

    let mesh_target_view_ref = if needs_post_processing {
        if let Some(config) = &output_config_opt {
            texture_pool.ensure_texture(
                &post_a_tex_name,
                config.resolution.0.max(1),
                config.resolution.1.max(1),
                surface_format,
                wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            );
        }
        Some(texture_pool.get_view(&post_a_tex_name))
    } else {
        None
    };

    let color_target_view_ref = if use_color_calib && use_edge_blend {
        if let Some(config) = &output_config_opt {
            texture_pool.ensure_texture(
                &post_b_tex_name,
                config.resolution.0.max(1),
                config.resolution.1.max(1),
                surface_format,
                wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            );
        }
        Some(texture_pool.get_view(&post_b_tex_name))
    } else {
        None
    };

    let (target_width, target_height) =
        output_config_opt.as_ref().map(|cfg| cfg.resolution).unwrap_or((1920, 1080));

    RenderTargets {
        use_edge_blend,
        use_color_calib,
        needs_post_processing,
        mesh_target_view_ref,
        color_target_view_ref,
        target_width,
        target_height,
        output_config_opt,
    }
}
