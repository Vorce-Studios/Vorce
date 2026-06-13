use super::RenderContext;

#[allow(clippy::too_many_arguments)]
pub(crate) fn process_post_effects(
    ctx: &mut RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    output_id: u64,
    view: &wgpu::TextureView,
    needs_post_processing: bool,
    use_color_calib: bool,
    use_edge_blend: bool,
    output_config_opt: &Option<vorce_core::output::OutputConfig>,
    mesh_target_view_ref: Option<std::sync::Arc<wgpu::TextureView>>,
    color_target_view_ref: Option<std::sync::Arc<wgpu::TextureView>>,
) {
    let queue = ctx.queue;
    if needs_post_processing {
        let mut current_view =
            mesh_target_view_ref.as_ref().map(|view_ref| view_ref.as_ref()).unwrap_or(view);

        if use_color_calib {
            if let (Some(color_renderer), Some(output_config)) =
                (ctx.color_calibration_renderer.as_ref(), output_config_opt.as_ref())
            {
                let color_target_view = color_target_view_ref
                    .as_ref()
                    .map(|view_ref| view_ref.as_ref())
                    .unwrap_or(view);
                let texture_bind_group = color_renderer.create_texture_bind_group(current_view);
                let uniform_buffer =
                    color_renderer.create_uniform_buffer(&output_config.color_calibration);
                let uniform_bind_group = color_renderer.create_uniform_bind_group(&uniform_buffer);

                let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("Color Calibration Pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        depth_slice: None,
                        view: color_target_view,
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

                color_renderer.render(&mut rpass, &texture_bind_group, &uniform_bind_group);
                current_view = color_target_view;
            }
        }

        if use_edge_blend {
            if let Some(edge_blend_renderer) = ctx.edge_blend_renderer.as_ref() {
                let texture_bind_group = ctx
                    .edge_blend_texture_cache
                    .entry(output_id)
                    .or_insert_with(|| edge_blend_renderer.create_texture_bind_group(current_view));
                *texture_bind_group = edge_blend_renderer.create_texture_bind_group(current_view);

                let config_to_use = if use_edge_blend {
                    output_config_opt
                        .as_ref()
                        .map(|config| config.edge_blend.clone())
                        .unwrap_or_default()
                } else {
                    vorce_core::EdgeBlendConfig::default()
                };

                // Simple hash for config changes
                use std::hash::Hasher;
                let mut hasher = std::collections::hash_map::DefaultHasher::new();
                hasher.write(&[config_to_use.left.enabled as u8]);
                hasher.write(&[config_to_use.right.enabled as u8]);
                hasher.write(&[config_to_use.top.enabled as u8]);
                hasher.write(&[config_to_use.bottom.enabled as u8]);
                hasher.write(&config_to_use.left.width.to_le_bytes());
                hasher.write(&config_to_use.right.width.to_le_bytes());
                hasher.write(&config_to_use.top.width.to_le_bytes());
                hasher.write(&config_to_use.bottom.width.to_le_bytes());
                hasher.write(&config_to_use.gamma.to_le_bytes());
                let config_hash = hasher.finish();

                let (uniform_buffer, uniform_bind_group, last_hash) =
                    ctx.edge_blend_cache.entry(output_id).or_insert_with(|| {
                        let buffer = edge_blend_renderer.create_uniform_buffer(&config_to_use);
                        let bind_group = edge_blend_renderer.create_uniform_bind_group(&buffer);
                        (buffer, bind_group, config_hash)
                    });

                if *last_hash != config_hash {
                    edge_blend_renderer.update_uniform_buffer(
                        queue,
                        uniform_buffer,
                        &config_to_use,
                    );
                    *last_hash = config_hash;
                }

                let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some(if use_edge_blend {
                        "Edge Blending Pass"
                    } else {
                        "Passthrough Pass"
                    }),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        depth_slice: None,
                        view, // Draw to the final surface view
                        resolve_target: None,

                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), // Clear previous if any
                            store: wgpu::StoreOp::Store,
                        },
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                    multiview_mask: None,
                });

                edge_blend_renderer.render(&mut rpass, texture_bind_group, uniform_bind_group);
            }
        }
    }
}
