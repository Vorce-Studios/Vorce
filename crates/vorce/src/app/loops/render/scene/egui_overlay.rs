pub(crate) fn render_egui_overlay(
    egui_renderer: &mut egui_wgpu::Renderer,
    encoder: &mut wgpu::CommandEncoder,
    view: &wgpu::TextureView,
    egui_data: Option<&(
        Vec<egui::ClippedPrimitive>,
        egui_wgpu::ScreenDescriptor,
        Vec<egui::TextureId>,
    )>,
) {
    if let Some((tris, screen_desc, free_textures)) = egui_data {
        for id in free_textures {
            egui_renderer.free_texture(id);
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

        egui_renderer.render(&mut render_pass.forget_lifetime(), tris, screen_desc);
    }
}
