use super::RenderContext;
use crate::app::core::app_struct::RuntimeRenderQueueItem;
use crate::app::loops::render::effects::build_effect_chain;
use crate::app::loops::render::logging::{clear_video_issue, should_log_video_issue};
use crate::app::loops::render::texture_gen::{
    ensure_missing_texture_fallback, generate_grid_texture,
};

#[allow(clippy::too_many_arguments)]
pub(crate) fn accumulate_layers(
    ctx: &mut RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    target_ops: &[RuntimeRenderQueueItem],
    real_output_id: u64,
    output_id: u64,
    is_preview_output: bool,
    ping_pong_0: &str,
    ping_pong_1: &str,
    scratch_name: &str,
    target_view: &wgpu::TextureView,
) {
    let device = ctx.device;
    let queue = ctx.queue;
    let mesh_renderer = &mut ctx.mesh_renderer;
    let video_log_times = &mut ctx.video_diagnostic_log_times;
    let mut active_accum = 0;
    // Clear initial accumulator
    {
        let accum_view = ctx.texture_pool.get_view(ping_pong_0);
        let _pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Clear Accumulator Pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                depth_slice: None,
                view: &accum_view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(if output_id == 0 {
                        wgpu::Color { r: 0.05, g: 0.05, b: 0.05, a: 1.0 }
                    } else {
                        wgpu::Color::BLACK
                    }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
    }

    // Accumulate Layers
    for item in target_ops {
        if item.diagnostics.iter().any(|diag| {
            matches!(diag.severity, crate::app::core::app_struct::DiagnosticSeverity::Error)
        }) {
            continue;
        }

        let module_id = item.module_id;
        let op = &item.render_op;
        let tex_name = if let Some(src_id) = op.source_part_id {
            format!("part_{}_{}", module_id, src_id)
        } else {
            "".to_string()
        };

        let source_view = if op.mapping_mode {
            let grid_tex_name = format!("grid_layer_{}", op.layer_part_id);
            if !ctx.texture_pool.has_texture(&grid_tex_name) {
                let width = 512;
                let height = 512;
                let data = generate_grid_texture(width, height, op.layer_part_id);
                ctx.texture_pool.ensure_texture(
                    &grid_tex_name,
                    width,
                    height,
                    wgpu::TextureFormat::Rgba8UnormSrgb,
                    wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                );
                ctx.texture_pool.upload_data(queue, &grid_tex_name, &data, width, height);
            }
            Some(ctx.texture_pool.get_view(&grid_tex_name))
        } else if ctx.texture_pool.has_texture(&tex_name) {
            clear_video_issue(
                video_log_times,
                format!(
                    "video-output-missing-texture:{real_output_id}:{module_id}:{}",
                    op.source_part_id.unwrap_or_default()
                ),
            );
            Some(ctx.texture_pool.get_view(&tex_name))
        } else if ctx.texture_pool.has_texture("bevy_output") {
            // Fallback for Bevy nodes
            clear_video_issue(
                video_log_times,
                format!(
                    "video-output-missing-texture:{real_output_id}:{module_id}:{}",
                    op.source_part_id.unwrap_or_default()
                ),
            );
            Some(ctx.texture_pool.get_view("bevy_output"))
        } else {
            if let Some(source_part_id) = op.source_part_id {
                let issue_key = format!(
                    "video-output-missing-texture:{real_output_id}:{module_id}:{source_part_id}"
                );
                if should_log_video_issue(video_log_times, issue_key) {
                    tracing::warn!(
                        "Fehler in Videoausgabe: {} {} kann Modul {} / Part {} nicht rendern, weil die erwartete Textur '{}' im TexturePool fehlt.",
                        if is_preview_output { "Preview fuer Output" } else { "Output" },
                        real_output_id,
                        module_id,
                        source_part_id,
                        tex_name
                    );
                }
            }
            // BLACK FALLBACK for missing textures
            ensure_missing_texture_fallback(ctx.texture_pool, queue);
            Some(ctx.texture_pool.get_view("missing_texture_fallback"))
        };

        if let Some(src_ref) = source_view {
            let mut final_source_view = src_ref.clone();

            if !op.effects.is_empty() {
                let effect_chain = build_effect_chain(&op.effects);
                if !effect_chain.effects.is_empty() {
                    let output_texture_name =
                        format!("effect_tmp_output_{}_layer_{}", real_output_id, op.layer_part_id);
                    let effect_width = 1024;
                    let effect_height = 1024;
                    ctx.texture_pool.ensure_texture(
                        &output_texture_name,
                        effect_width,
                        effect_height,
                        wgpu::TextureFormat::Bgra8UnormSrgb,
                        wgpu::TextureUsages::TEXTURE_BINDING
                            | wgpu::TextureUsages::RENDER_ATTACHMENT
                            | wgpu::TextureUsages::COPY_DST,
                    );

                    let output_effect_view = ctx.texture_pool.get_view(&output_texture_name);
                    if is_preview_output {
                        ctx.preview_effect_chain_renderer.apply_chain(
                            encoder,
                            &src_ref,
                            &output_effect_view,
                            &effect_chain,
                            ctx.shader_graph_manager,
                            0.0,
                            effect_width,
                            effect_height,
                        );
                    } else {
                        ctx.effect_chain_renderer.apply_chain(
                            encoder,
                            &src_ref,
                            &output_effect_view,
                            &effect_chain,
                            ctx.shader_graph_manager,
                            0.0,
                            effect_width,
                            effect_height,
                        );
                    }

                    final_source_view = output_effect_view;
                }
            }

            let transform = glam::Mat4::from_scale_rotation_translation(
                glam::vec3(op.source_props.scale_x, op.source_props.scale_y, 1.0),
                glam::Quat::from_rotation_z(op.source_props.rotation.to_radians()),
                glam::vec3(op.source_props.offset_x, op.source_props.offset_y, 0.0),
            );
            let uniform_bind_group = mesh_renderer.get_uniform_bind_group_with_source_props(
                queue,
                transform,
                op.opacity * op.source_props.opacity,
                op.source_props.flip_horizontal,
                op.source_props.flip_vertical,
                op.source_props.brightness,
                op.source_props.contrast,
                op.source_props.saturation,
                op.source_props.hue_shift,
            );

            let texture_bind_group = mesh_renderer.get_texture_bind_group(&final_source_view);
            let (vb, ib, cnt) = ctx.mesh_buffer_cache.get_buffers(
                device,
                queue,
                op.layer_part_id,
                &op.mesh.to_mesh(),
            );

            let blend_mode = op.blend_mode.unwrap_or(vorce_core::module::BlendModeType::Normal);
            let is_normal_blend = matches!(blend_mode, vorce_core::module::BlendModeType::Normal);

            let current_accum_name = if active_accum == 0 { &ping_pong_0 } else { &ping_pong_1 };
            let render_target_name =
                if is_normal_blend { current_accum_name } else { &scratch_name };

            let render_target_view = ctx.texture_pool.get_view(render_target_name);

            {
                let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("Mesh Layer Pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        depth_slice: None,
                        view: &render_target_view,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: if is_normal_blend {
                                wgpu::LoadOp::Load
                            } else {
                                wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT)
                            },
                            store: wgpu::StoreOp::Store,
                        },
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                    multiview_mask: None,
                });

                mesh_renderer.draw(
                    &mut rpass,
                    vb,
                    ib,
                    cnt,
                    &uniform_bind_group,
                    &texture_bind_group,
                    true,
                );
            }

            if !is_normal_blend {
                let next_accum = (active_accum + 1) % 2;
                let next_accum_name = if next_accum == 0 { &ping_pong_0 } else { &ping_pong_1 };

                let base_view = ctx.texture_pool.get_view(current_accum_name);
                let blend_view = ctx.texture_pool.get_view(scratch_name);
                let out_view = ctx.texture_pool.get_view(next_accum_name);

                // Map ModuleBlendModeType to LayerBlendMode
                // Note: The UI/core might use different enums, we need to convert to vorce_core::BlendMode
                let core_blend_mode = match blend_mode {
                    vorce_core::module::BlendModeType::Normal => {
                        vorce_core::layer::BlendMode::Normal
                    }
                    vorce_core::module::BlendModeType::Add => vorce_core::layer::BlendMode::Add,
                    vorce_core::module::BlendModeType::Multiply => {
                        vorce_core::layer::BlendMode::Multiply
                    }
                    vorce_core::module::BlendModeType::Screen => {
                        vorce_core::layer::BlendMode::Screen
                    }
                    vorce_core::module::BlendModeType::Overlay => {
                        vorce_core::layer::BlendMode::Overlay
                    }
                    vorce_core::module::BlendModeType::Difference => {
                        vorce_core::layer::BlendMode::Difference
                    }
                    vorce_core::module::BlendModeType::Exclusion => {
                        vorce_core::layer::BlendMode::Exclusion
                    }
                };

                let bind_group = ctx.compositor.create_bind_group(&base_view, &blend_view);
                let uniform_bind_group =
                    ctx.compositor.get_uniform_bind_group(queue, core_blend_mode, 1.0);

                // We need a full screen quad to composite
                // We can use the mesh_buffer_cache for a full screen quad or let the compositor do it internally?
                // Compositor handles its own quad in `composite`
                // Wait, `composite` needs vertex and index buffers.
                // Looking at compositor.rs, it doesn't provide default buffers, we must pass them.
                // We can get a quad from mesh_buffer_cache if we pass layer 0 and a full screen quad?
                // Actually, let's look at `vorce_render::Compositor::composite` signature:
                // composite(&mut render_pass, vertex_buffer, index_buffer, bind_group, uniform_bind_group)
                // Let's use mesh_buffer_cache with a unit quad.
                let quad_mesh = vorce_core::module::MeshType::default().to_mesh();
                let (quad_vb, quad_ib, _quad_cnt) =
                    ctx.mesh_buffer_cache.get_buffers(device, queue, 999999, &quad_mesh);

                let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("Compositor Pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        depth_slice: None,
                        view: &out_view,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                            store: wgpu::StoreOp::Store,
                        },
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                    multiview_mask: None,
                });

                ctx.compositor.composite(
                    &mut rpass,
                    quad_vb,
                    quad_ib,
                    &bind_group,
                    &uniform_bind_group,
                );

                active_accum = next_accum;
            }
        }
    }

    // Copy final accumulator to target_view
    {
        let final_accum_name = if active_accum == 0 { &ping_pong_0 } else { &ping_pong_1 };
        let final_accum_view = ctx.texture_pool.get_view(final_accum_name);

        let quad_mesh = vorce_core::module::MeshType::default().to_mesh();
        let (quad_vb, quad_ib, _quad_cnt) =
            ctx.mesh_buffer_cache.get_buffers(device, queue, 999998, &quad_mesh);

        let bind_group = ctx.compositor.create_bind_group(&final_accum_view, &final_accum_view); // second view ignored for Normal blend
        let uniform_bind_group =
            ctx.compositor.get_uniform_bind_group(queue, vorce_core::layer::BlendMode::Normal, 1.0);

        let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Copy to Target View Pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                depth_slice: None,
                view: target_view,
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

        ctx.compositor.composite(&mut rpass, quad_vb, quad_ib, &bind_group, &uniform_bind_group);
    }
}
