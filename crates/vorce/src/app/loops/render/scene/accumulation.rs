use crate::app::core::app_struct::RuntimeRenderQueueItem;
use crate::app::loops::render::effects::build_effect_chain;
use crate::app::loops::render::logging::{clear_video_issue, should_log_video_issue};
use crate::app::loops::render::texture_gen::{
    ensure_missing_texture_fallback, generate_grid_texture,
};

#[allow(clippy::too_many_arguments)]
pub(crate) fn render_accumulation(
    layer_ping_pong: &[String; 2],
    texture_pool: &vorce_render::TexturePool,
    surface_format: wgpu::TextureFormat,
    queue: &wgpu::Queue,
    video_diagnostic_log_times: &mut std::collections::HashMap<String, std::time::Instant>,
    preview_effect_chain_renderer: &mut vorce_render::EffectChainRenderer,
    effect_chain_renderer: &mut vorce_render::EffectChainRenderer,
    shader_graph_manager: &vorce_render::ShaderGraphManager,
    mesh_renderer: &mut vorce_render::MeshRenderer,
    mesh_buffer_cache: &mut vorce_render::MeshBufferCache,
    device: &wgpu::Device,
    compositor: &mut vorce_render::Compositor,
    target_ops: &[RuntimeRenderQueueItem],
    encoder: &mut wgpu::CommandEncoder,
    target_view: &wgpu::TextureView,
    is_preview_output: bool,
    output_id: u64,
    real_output_id: u64,
    target_width: u32,
    target_height: u32,
) {
    let ping_pong_0 = format!("{}_{}", layer_ping_pong[0], output_id);
    let ping_pong_1 = format!("{}_{}", layer_ping_pong[1], output_id);
    let scratch_name = format!("layer_scratch_{}", output_id);

    texture_pool.ensure_texture(
        &ping_pong_0,
        target_width.max(1),
        target_height.max(1),
        surface_format,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
    );
    texture_pool.ensure_texture(
        &ping_pong_1,
        target_width.max(1),
        target_height.max(1),
        surface_format,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
    );
    texture_pool.ensure_texture(
        &scratch_name,
        target_width.max(1),
        target_height.max(1),
        surface_format,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
    );

    let mut active_accum = 0;

    {
        let accum_view = texture_pool.get_view(&ping_pong_0);
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
            if !texture_pool.has_texture(&grid_tex_name) {
                let width = 512;
                let height = 512;
                let data = generate_grid_texture(width, height, op.layer_part_id);
                texture_pool.ensure_texture(
                    &grid_tex_name,
                    width,
                    height,
                    wgpu::TextureFormat::Rgba8UnormSrgb,
                    wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                );
                texture_pool.upload_data(queue, &grid_tex_name, &data, width, height);
            }
            Some(texture_pool.get_view(&grid_tex_name))
        } else if texture_pool.has_texture(&tex_name) {
            clear_video_issue(
                video_diagnostic_log_times,
                format!(
                    "video-output-missing-texture:{real_output_id}:{module_id}:{}",
                    op.source_part_id.unwrap_or_default()
                ),
            );
            Some(texture_pool.get_view(&tex_name))
        } else if texture_pool.has_texture("bevy_output") {
            clear_video_issue(
                video_diagnostic_log_times,
                format!(
                    "video-output-missing-texture:{real_output_id}:{module_id}:{}",
                    op.source_part_id.unwrap_or_default()
                ),
            );
            Some(texture_pool.get_view("bevy_output"))
        } else {
            if let Some(source_part_id) = op.source_part_id {
                let issue_key = format!(
                    "video-output-missing-texture:{real_output_id}:{module_id}:{source_part_id}"
                );
                if should_log_video_issue(video_diagnostic_log_times, issue_key) {
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
            ensure_missing_texture_fallback(texture_pool, queue);
            Some(texture_pool.get_view("missing_texture_fallback"))
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
                    texture_pool.ensure_texture(
                        &output_texture_name,
                        effect_width,
                        effect_height,
                        wgpu::TextureFormat::Bgra8UnormSrgb,
                        wgpu::TextureUsages::TEXTURE_BINDING
                            | wgpu::TextureUsages::RENDER_ATTACHMENT
                            | wgpu::TextureUsages::COPY_DST,
                    );

                    let output_effect_view = texture_pool.get_view(&output_texture_name);
                    if is_preview_output {
                        preview_effect_chain_renderer.apply_chain(
                            encoder,
                            &src_ref,
                            &output_effect_view,
                            &effect_chain,
                            shader_graph_manager,
                            0.0,
                            effect_width,
                            effect_height,
                        );
                    } else {
                        effect_chain_renderer.apply_chain(
                            encoder,
                            &src_ref,
                            &output_effect_view,
                            &effect_chain,
                            shader_graph_manager,
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
            let (vb, ib, cnt) =
                mesh_buffer_cache.get_buffers(device, queue, op.layer_part_id, &op.mesh.to_mesh());

            let blend_mode = op.blend_mode.unwrap_or(vorce_core::module::BlendModeType::Normal);
            let is_normal_blend = matches!(blend_mode, vorce_core::module::BlendModeType::Normal);

            let current_accum_name = if active_accum == 0 { &ping_pong_0 } else { &ping_pong_1 };
            let render_target_name =
                if is_normal_blend { current_accum_name } else { &scratch_name };

            let render_target_view = texture_pool.get_view(render_target_name);

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

                let base_view = texture_pool.get_view(current_accum_name);
                let blend_view = texture_pool.get_view(&scratch_name);
                let out_view = texture_pool.get_view(next_accum_name);

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

                let bind_group = compositor.create_bind_group(&base_view, &blend_view);
                let uniform_bind_group =
                    compositor.get_uniform_bind_group(queue, core_blend_mode, 1.0);

                let quad_mesh = vorce_core::module::MeshType::default().to_mesh();
                let (quad_vb, quad_ib, _quad_cnt) =
                    mesh_buffer_cache.get_buffers(device, queue, 999999, &quad_mesh);

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

                compositor.composite(
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

    {
        let final_accum_name = if active_accum == 0 { &ping_pong_0 } else { &ping_pong_1 };
        let final_accum_view = texture_pool.get_view(final_accum_name);

        let quad_mesh = vorce_core::module::MeshType::default().to_mesh();
        let (quad_vb, quad_ib, _quad_cnt) =
            mesh_buffer_cache.get_buffers(device, queue, 999998, &quad_mesh);

        let bind_group = compositor.create_bind_group(&final_accum_view, &final_accum_view);
        let uniform_bind_group =
            compositor.get_uniform_bind_group(queue, vorce_core::layer::BlendMode::Normal, 1.0);

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

        compositor.composite(&mut rpass, quad_vb, quad_ib, &bind_group, &uniform_bind_group);
    }
}
