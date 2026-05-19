use crate::app::core::app_struct::RuntimeRenderQueueItem;
use anyhow::Result;

use super::PREVIEW_FLAG;

pub(crate) struct RenderContext<'a> {
    pub device: &'a wgpu::Device,
    pub queue: &'a wgpu::Queue,
    pub surface_format: wgpu::TextureFormat,
    pub render_queue: &'a std::collections::HashMap<u64, Vec<RuntimeRenderQueueItem>>,
    pub output_manager: &'a vorce_core::output::OutputManager,
    pub edge_blend_renderer: &'a Option<vorce_render::EdgeBlendRenderer>,
    pub color_calibration_renderer: &'a Option<vorce_render::ColorCalibrationRenderer>,
    pub edge_blend_cache:
        &'a mut std::collections::HashMap<u64, (wgpu::Buffer, wgpu::BindGroup, u64)>,
    pub edge_blend_texture_cache: &'a mut std::collections::HashMap<u64, wgpu::BindGroup>,
    pub mesh_renderer: &'a mut vorce_render::MeshRenderer,
    pub effect_chain_renderer: &'a mut vorce_render::EffectChainRenderer,
    pub preview_effect_chain_renderer: &'a mut vorce_render::EffectChainRenderer,
    pub shader_graph_manager: &'a vorce_render::ShaderGraphManager,
    pub texture_pool: &'a vorce_render::TexturePool,
    pub compositor: &'a mut vorce_render::Compositor,
    pub layer_ping_pong: &'a mut [String; 2],
    pub _dummy_view: &'a Option<std::sync::Arc<wgpu::TextureView>>,
    pub mesh_buffer_cache: &'a mut vorce_render::MeshBufferCache,
    pub egui_renderer: &'a mut egui_wgpu::Renderer,
    pub video_diagnostic_log_times: &'a mut std::collections::HashMap<String, std::time::Instant>,
}

pub(crate) fn render_content(
    ctx: RenderContext<'_>,
    output_id: u64,
    encoder: &mut wgpu::CommandEncoder,
    view: &wgpu::TextureView,
    egui_data: Option<&(
        Vec<egui::ClippedPrimitive>,
        egui_wgpu::ScreenDescriptor,
        Vec<egui::TextureId>,
    )>,
) -> Result<()> {
    let is_preview_output = (output_id & PREVIEW_FLAG) != 0;
    let real_output_id = output_id & !PREVIEW_FLAG;

    let empty_vec = Vec::new();
    let target_ops = ctx.render_queue.get(&real_output_id).unwrap_or(&empty_vec);

    crate::app::loops::render::scene::diagnostics::process_diagnostics(
        ctx.video_diagnostic_log_times,
        target_ops,
        is_preview_output,
        real_output_id,
        output_id,
    );

    if crate::app::loops::render::scene::clear::process_clear_pass(
        encoder,
        view,
        target_ops.is_empty(),
        output_id,
    ) {
        return Ok(());
    }

    let targets = crate::app::loops::render::scene::targets::setup_render_targets(
        ctx.output_manager,
        ctx.texture_pool,
        ctx.surface_format,
        real_output_id,
        output_id,
        ctx.edge_blend_renderer.is_some(),
        ctx.color_calibration_renderer.is_some(),
    );

    let target_view_ref = if targets.needs_post_processing {
        targets.mesh_target_view_ref.as_deref().unwrap_or(view)
    } else {
        view
    };

    crate::app::loops::render::scene::accumulation::render_accumulation(
        ctx.layer_ping_pong,
        ctx.texture_pool,
        ctx.surface_format,
        ctx.queue,
        ctx.video_diagnostic_log_times,
        ctx.preview_effect_chain_renderer,
        ctx.effect_chain_renderer,
        ctx.shader_graph_manager,
        ctx.mesh_renderer,
        ctx.mesh_buffer_cache,
        ctx.device,
        ctx.compositor,
        target_ops,
        encoder,
        target_view_ref,
        is_preview_output,
        output_id,
        real_output_id,
        targets.target_width,
        targets.target_height,
    );

    if targets.needs_post_processing {
        crate::app::loops::render::scene::post_processing::render_post_processing(
            ctx.color_calibration_renderer,
            ctx.edge_blend_renderer,
            ctx.edge_blend_texture_cache,
            ctx.edge_blend_cache,
            ctx.queue,
            encoder,
            view,
            targets.mesh_target_view_ref.as_ref(),
            targets.color_target_view_ref.as_ref(),
            output_id,
            targets.use_edge_blend,
            targets.use_color_calib,
            targets.output_config_opt.as_ref(),
        );
    }

    if output_id == 0 {
        crate::app::loops::render::scene::egui_overlay::render_egui_overlay(
            ctx.egui_renderer,
            encoder,
            view,
            egui_data,
        );
    }

    Ok(())
}
