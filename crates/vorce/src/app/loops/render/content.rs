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

    if target_ops.is_empty() && output_id != 0 {
        let _pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Clear Pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                depth_slice: None,
                view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        return Ok(());
    }

    let output_config_opt = ctx.output_manager.get_output(real_output_id).cloned();
    let use_edge_blend = output_config_opt
        .as_ref()
        .map(|cfg| {
            cfg.edge_blend.left.enabled
                || cfg.edge_blend.right.enabled
                || cfg.edge_blend.top.enabled
                || cfg.edge_blend.bottom.enabled
        })
        .unwrap_or(false)
        && ctx.edge_blend_renderer.is_some();
    let use_color_calib = output_config_opt
        .as_ref()
        .map(|cfg| cfg.color_calibration != vorce_core::ColorCalibration::default())
        .unwrap_or(false)
        && ctx.color_calibration_renderer.is_some();

    let needs_post_processing = use_edge_blend || use_color_calib;

    let post_a_tex_name = format!("output_{}_post_a", output_id);
    let post_b_tex_name = format!("output_{}_post_b", output_id);
    let mesh_target_view_ref = if needs_post_processing {
        if let Some(config) = &output_config_opt {
            ctx.texture_pool.ensure_texture(
                &post_a_tex_name,
                config.resolution.0.max(1),
                config.resolution.1.max(1),
                ctx.surface_format,
                wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            );
        }
        Some(ctx.texture_pool.get_view(&post_a_tex_name))
    } else {
        None
    };
    let color_target_view_ref = if use_color_calib && use_edge_blend {
        if let Some(config) = &output_config_opt {
            ctx.texture_pool.ensure_texture(
                &post_b_tex_name,
                config.resolution.0.max(1),
                config.resolution.1.max(1),
                ctx.surface_format,
                wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            );
        }
        Some(ctx.texture_pool.get_view(&post_b_tex_name))
    } else {
        None
    };

    let target_view =
        if needs_post_processing { mesh_target_view_ref.as_deref().unwrap_or(view) } else { view };

    let (target_width, target_height) =
        output_config_opt.as_ref().map(|cfg| cfg.resolution).unwrap_or((1920, 1080));

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
        target_view,
        is_preview_output,
        output_id,
        real_output_id,
        target_width,
        target_height,
    );

    if needs_post_processing {
        crate::app::loops::render::scene::post_processing::render_post_processing(
            ctx.color_calibration_renderer,
            ctx.edge_blend_renderer,
            ctx.edge_blend_texture_cache,
            ctx.edge_blend_cache,
            ctx.queue,
            encoder,
            view,
            mesh_target_view_ref.as_ref(),
            color_target_view_ref.as_ref(),
            output_id,
            use_edge_blend,
            use_color_calib,
            output_config_opt.as_ref(),
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
