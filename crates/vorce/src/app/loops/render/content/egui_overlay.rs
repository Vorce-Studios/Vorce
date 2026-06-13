use super::RenderContext;

pub(crate) fn render_egui(
    ctx: &mut RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    output_id: u64,
    view: &wgpu::TextureView,
    egui_data: Option<&(
        Vec<egui::ClippedPrimitive>,
        egui_wgpu::ScreenDescriptor,
        Vec<egui::TextureId>,
    )>,
) {
    if output_id == 0 {
        if let Some((tris, screen_desc, free_textures)) = egui_data {
            // Free textures from previous frames
            for id in free_textures {
                ctx.egui_renderer.free_texture(id);
            }

            let render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Egui Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    depth_slice: None,
                    view,
                    resolve_target: None,

                    ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });

            // Render egui UI
            ctx.egui_renderer.render(&mut render_pass.forget_lifetime(), tris, screen_desc);
        }
    }
}
