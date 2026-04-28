//! Main application render loop.

use crate::app::core::app_struct::App;
use crate::app::ui_layout;
use anyhow::Result;
#[cfg(feature = "ndi")]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(feature = "ndi")]
use std::sync::Arc;
use vorce_core::OutputId;

mod content;
mod effects;
mod logging;
mod previews;
mod texture_gen;

use content::*;
use previews::*;

pub(crate) const PREVIEW_FLAG: u64 = 1u64 << 63;

/// Default resolution for NDI output when not specified.
#[allow(dead_code)]
const NDI_OUTPUT_DEFAULT_WIDTH: u32 = 1920;
#[allow(dead_code)]
const NDI_OUTPUT_DEFAULT_HEIGHT: u32 = 1080;

/// Renders the UI or content for the given output ID.
#[allow(deprecated)]
pub fn render(app: &mut App, output_id: OutputId) -> Result<()> {
    // Clone device Arc to create encoder without borrowing self
    let device = app.backend.device.clone();

    let mut encoder = device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("Render Encoder") });

    // Batch render passes.
    app.mesh_renderer.begin_frame();
    app.effect_chain_renderer.begin_frame();
    app.preview_effect_chain_renderer.begin_frame();

    if output_id == 0 {
        // Sync Texture Previews
        prepare_texture_previews(app, &mut encoder);
        // Update Bevy Texture
        if let Some(runner) = &app.bevy_runner {
            let runner: &vorce_bevy::BevyRunner = runner;
            if let Some((data, width, height)) = runner.get_image_data() {
                let tex_name = "bevy_output";
                app.texture_pool.ensure_texture(
                    tex_name,
                    width,
                    height,
                    wgpu::TextureFormat::Bgra8UnormSrgb,
                    wgpu::TextureUsages::TEXTURE_BINDING
                        | wgpu::TextureUsages::COPY_DST
                        | wgpu::TextureUsages::RENDER_ATTACHMENT,
                );

                app.texture_pool.upload_data(&app.backend.queue, tex_name, &data, width, height);
            }
        }
    }

    // --- UI PASS (Output 0 only) ---
    let mut egui_render_data = None;

    if output_id == 0 {
        // 1. Get Input and Window Info (Short-lived borrow)
        let (raw_input, screen_descriptor) = {
            let window_context = match app.window_manager.get(0) {
                Some(ctx) => ctx,
                None => return Ok(()),
            };

            let input = app.egui_state.take_egui_input(&window_context.window);
            let desc = egui_wgpu::ScreenDescriptor {
                size_in_pixels: [
                    window_context.surface_config.width,
                    window_context.surface_config.height,
                ],
                pixels_per_point: app.egui_context.pixels_per_point(),
            };
            (input, desc)
        };

        // 2. Run UI Pass (SAFE: app is now available mutably)
        let egui_ctx = app.egui_context.clone();
        let full_output = egui_ctx.run(raw_input, |ctx| {
            ui_layout::show(ctx, app);
        });

        // 3. Handle Output (Requires another short-lived borrow of window)
        {
            let window_context = app.window_manager.get(0).unwrap();
            app.egui_state
                .handle_platform_output(&window_context.window, full_output.platform_output);
        }

        // 4. Update Textures and Buffers
        let tris =
            app.egui_context.tessellate(full_output.shapes, app.egui_context.pixels_per_point());

        for (id, delta) in full_output.textures_delta.set {
            app.egui_renderer.update_texture(&device, &app.backend.queue, id, &delta);
        }

        app.egui_renderer.update_buffers(
            &device,
            &app.backend.queue,
            &mut encoder,
            &tris,
            &screen_descriptor,
        );

        egui_render_data = Some((tris, screen_descriptor, full_output.textures_delta.free));
    }

    // --- RENDER PASS ---
    {
        let window_context = match app.window_manager.get(output_id) {
            Some(ctx) => ctx,
            None => return Ok(()),
        };

        let surface_texture = match window_context.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(texture)
            | wgpu::CurrentSurfaceTexture::Suboptimal(texture) => texture,
            wgpu::CurrentSurfaceTexture::Timeout | wgpu::CurrentSurfaceTexture::Occluded => {
                return Ok(());
            }
            wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                window_context
                    .surface
                    .configure(&app.backend.device, &window_context.surface_config);
                return Ok(());
            }
            wgpu::CurrentSurfaceTexture::Validation => {
                anyhow::bail!("failed to acquire surface texture due to validation error");
            }
        };
        let view = surface_texture.texture.create_view(&wgpu::TextureViewDescriptor::default());

        // Render Content
        render_content(
            RenderContext {
                device: &app.backend.device,
                queue: &app.backend.queue,
                surface_format: app.backend.surface_format(),
                render_queue: &app.render_queue.items,
                output_manager: &app.state.output_manager,
                edge_blend_renderer: &app.edge_blend_renderer,
                color_calibration_renderer: &app.color_calibration_renderer,
                edge_blend_cache: &mut app.edge_blend_cache,
                edge_blend_texture_cache: &mut app.edge_blend_texture_cache,
                mesh_renderer: &mut app.mesh_renderer,
                effect_chain_renderer: &mut app.effect_chain_renderer,
                preview_effect_chain_renderer: &mut app.preview_effect_chain_renderer,
                shader_graph_manager: &app.shader_graph_manager,
                texture_pool: &app.texture_pool,
                compositor: &mut app.compositor,
                layer_ping_pong: &mut app.layer_ping_pong,
                _dummy_view: &app.dummy_view,
                mesh_buffer_cache: &mut app.mesh_buffer_cache,
                egui_renderer: &mut app.egui_renderer,
                video_diagnostic_log_times: &mut app.video_diagnostic_log_times,
            },
            output_id,
            &mut encoder,
            &view,
            egui_render_data.as_ref(),
        )?;

        // --- NDI Readback (if enabled) ---
        #[cfg(feature = "ndi")]
        {
            // Find if this output has an NDI sender
            let part_id = app.render_queue.items.get(&output_id).and_then(|items| {
                items.iter().find_map(|item| match &item.render_op.output_type {
                    vorce_core::module::OutputType::Projector { id, .. } if *id == output_id => {
                        Some(item.render_op.output_part_id)
                    }
                    vorce_core::module::OutputType::NdiOutput { .. }
                        if output_id == item.render_op.output_part_id =>
                    {
                        Some(item.render_op.output_part_id)
                    }
                    _ => None,
                })
            });

            if let Some(pid) = part_id {
                if let Some(sender) = app.ndi_senders.get_mut(&pid) {
                    let mut buffer_ready = false;
                    if let Some((buffer, mapping_requested)) = app.ndi_readbacks.get_mut(&output_id)
                    {
                        if mapping_requested.load(Ordering::SeqCst) {
                            let _ = app.backend.device.poll(wgpu::PollType::Wait {
                                submission_index: None,
                                timeout: Some(std::time::Duration::from_millis(0)),
                            });

                            if !buffer.slice(..).get_mapped_range().is_empty() {
                                {
                                    let view = buffer.slice(..).get_mapped_range();
                                    let frame_data = view.to_vec();
                                    let width = window_context.surface_config.width;
                                    let height = window_context.surface_config.height;

                                    let video_frame = vorce_io::format::VideoFrame {
                                        data: vorce_io::format::FrameData::Cpu(Arc::new(
                                            frame_data,
                                        )),
                                        format: vorce_io::format::VideoFormat {
                                            width,
                                            height,
                                            pixel_format: vorce_io::format::PixelFormat::BGRA8,
                                            frame_rate: 60.0,
                                        },
                                        timestamp: std::time::Duration::from_secs(0),
                                        metadata: Default::default(),
                                    };

                                    if let Err(e) = sender.send_frame(&video_frame) {
                                        tracing::warn!("Failed to send NDI frame: {}", e);
                                    }
                                }
                                buffer.unmap();
                                mapping_requested.store(false, Ordering::SeqCst);
                                buffer_ready = true;
                            }
                        } else {
                            buffer_ready = true;
                        }
                    } else {
                        let width = window_context.surface_config.width;
                        let height = window_context.surface_config.height;
                        let bytes_per_pixel = 4;
                        let unpadded_bytes_per_row = width * bytes_per_pixel;
                        let padding = (256 - unpadded_bytes_per_row % 256) % 256;
                        let bytes_per_row = unpadded_bytes_per_row + padding;
                        let size = (bytes_per_row * height) as u64;

                        let buffer = app.backend.device.create_buffer(&wgpu::BufferDescriptor {
                            label: Some("NDI Readback Buffer"),
                            size,
                            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                            mapped_at_creation: false,
                        });
                        app.ndi_readbacks.insert(
                            output_id,
                            (buffer, std::sync::Arc::new(AtomicBool::new(false))),
                        );
                        buffer_ready = true;
                    }

                    if buffer_ready {
                        if let Some((buffer, mapping_requested)) =
                            app.ndi_readbacks.get_mut(&output_id)
                        {
                            let width = window_context.surface_config.width;
                            let height = window_context.surface_config.height;
                            let bytes_per_pixel = 4;
                            let unpadded_bytes_per_row = width * bytes_per_pixel;
                            let padding = (256 - unpadded_bytes_per_row % 256) % 256;
                            let bytes_per_row = unpadded_bytes_per_row + padding;

                            encoder.copy_texture_to_buffer(
                                wgpu::TexelCopyTextureInfo {
                                    texture: &surface_texture.texture,
                                    mip_level: 0,
                                    origin: wgpu::Origin3d::ZERO,
                                    aspect: wgpu::TextureAspect::All,
                                },
                                wgpu::TexelCopyBufferInfo {
                                    buffer,
                                    layout: wgpu::TexelCopyBufferLayout {
                                        offset: 0,
                                        bytes_per_row: Some(bytes_per_row),
                                        rows_per_image: Some(height),
                                    },
                                },
                                wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
                            );

                            let slice = buffer.slice(..);
                            let requested_clone = mapping_requested.clone();
                            slice.map_async(wgpu::MapMode::Read, move |res| {
                                if res.is_ok() {
                                    requested_clone.store(true, Ordering::SeqCst);
                                }
                            });
                        }
                    }
                }
            }
        }

        app.backend.queue.submit(std::iter::once(encoder.finish()));
        window_context.window.pre_present_notify();
        surface_texture.present();
    }

    // --- Virtual Outputs Pass (NDI) ---
    // Handle NDI senders that don't have a physical window
    if output_id == 0 {
        #[cfg(feature = "ndi")]
        {
            // Collect all NDI senders that need offscreen rendering
            let mut ndi_virtual_tasks: Vec<(vorce_core::module::ModulePartId, String, u32, u32)> =
                Vec::new();

            for (&part_id, _sender) in &app.ndi_senders {
                // Check if this part_id is already being handled by a physical window pass
                // We check if any output_id > 0 has this part_id in its render queue
                let is_physical = app.render_queue.items.iter().any(|(&oid, items)| {
                    oid != 0 && items.iter().any(|item| item.render_op.output_part_id == part_id)
                });

                if !is_physical {
                    // It's a virtual output (no window), so we need offscreen rendering.
                    // We need to find its intended resolution from the module graph.
                    if let Some(module) = app
                        .state
                        .module_manager
                        .modules()
                        .iter()
                        .find(|m| m.parts.iter().any(|p| p.id == part_id))
                    {
                        if let Some(part) = module.parts.iter().find(|p| p.id == part_id) {
                            match &part.part_type {
                                vorce_core::module::ModulePartType::Output(
                                    vorce_core::module::OutputType::NdiOutput {
                                        name,
                                        width,
                                        height,
                                    },
                                ) => {
                                    ndi_virtual_tasks.push((
                                        part_id,
                                        name.clone(),
                                        *width,
                                        *height,
                                    ));
                                }
                                vorce_core::module::ModulePartType::Output(
                                    vorce_core::module::OutputType::Projector {
                                        ndi_stream_name,
                                        output_width,
                                        output_height,
                                        ..
                                    },
                                ) => {
                                    ndi_virtual_tasks.push((
                                        part_id,
                                        ndi_stream_name.clone(),
                                        *output_width,
                                        *output_height,
                                    ));
                                }
                                _ => {}
                            }
                        }
                    }
                }
            }

            for (part_id, _stream_name, width, height) in ndi_virtual_tasks {
                // Ensure offscreen texture exists for this NDI output
                let tex_size = (width.max(128), height.max(128));
                let needs_texture =
                    if let Some((tex, _view)) = app.ndi_offscreen_textures.get(&part_id) {
                        tex.width() != tex_size.0 || tex.height() != tex_size.1
                    } else {
                        true
                    };

                if needs_texture {
                    let texture = app.backend.device.create_texture(&wgpu::TextureDescriptor {
                        label: Some("NDI Offscreen Texture"),
                        size: wgpu::Extent3d {
                            width: tex_size.0,
                            height: tex_size.1,
                            depth_or_array_layers: 1,
                        },
                        mip_level_count: 1,
                        sample_count: 1,
                        dimension: wgpu::TextureDimension::D2,
                        format: app.backend.surface_format(),
                        usage: wgpu::TextureUsages::RENDER_ATTACHMENT
                            | wgpu::TextureUsages::TEXTURE_BINDING
                            | wgpu::TextureUsages::COPY_SRC,
                        view_formats: &[],
                    });
                    let view = std::sync::Arc::new(
                        texture.create_view(&wgpu::TextureViewDescriptor::default()),
                    );
                    app.ndi_offscreen_textures.insert(part_id, (texture, view));
                }

                if let Some((texture, view)) = app.ndi_offscreen_textures.get(&part_id) {
                    // Create a new encoder for offscreen rendering
                    let mut offscreen_encoder = app.backend.device.create_command_encoder(
                        &wgpu::CommandEncoderDescriptor { label: Some("NDI Offscreen Encoder") },
                    );

                    // Render content to offscreen texture using the part_id as the output ID
                    render_content(
                        RenderContext {
                            device: &app.backend.device,
                            queue: &app.backend.queue,
                            surface_format: app.backend.surface_format(),
                            render_queue: &app.render_queue.items,
                            output_manager: &app.state.output_manager,
                            edge_blend_renderer: &app.edge_blend_renderer,
                            color_calibration_renderer: &app.color_calibration_renderer,
                            edge_blend_cache: &mut app.edge_blend_cache,
                            edge_blend_texture_cache: &mut app.edge_blend_texture_cache,
                            mesh_renderer: &mut app.mesh_renderer,
                            effect_chain_renderer: &mut app.effect_chain_renderer,
                            preview_effect_chain_renderer: &mut app.preview_effect_chain_renderer,
                            shader_graph_manager: &app.shader_graph_manager,
                            texture_pool: &app.texture_pool,
                            compositor: &mut app.compositor,
                            layer_ping_pong: &mut app.layer_ping_pong,
                            _dummy_view: &app.dummy_view,
                            mesh_buffer_cache: &mut app.mesh_buffer_cache,
                            egui_renderer: &mut app.egui_renderer,
                            video_diagnostic_log_times: &mut app.video_diagnostic_log_times,
                        },
                        part_id,
                        &mut offscreen_encoder,
                        view,
                        None,
                    )?;

                    // Readback and send via NDI
                    if let Some(sender) = app.ndi_senders.get_mut(&part_id) {
                        let width = tex_size.0;
                        let height = tex_size.1;
                        let bytes_per_pixel = 4;
                        let unpadded_bytes_per_row = width * bytes_per_pixel;
                        let padding = (256 - unpadded_bytes_per_row % 256) % 256;
                        let bytes_per_row = unpadded_bytes_per_row + padding;
                        let buffer_size = (bytes_per_row * height) as u64;

                        // Get or create readback buffer
                        let (buffer, mapping_requested) = app
                            .ndi_readbacks
                            .entry(part_id)
                            .or_insert_with(|| {
                                let buffer =
                                    app.backend.device.create_buffer(&wgpu::BufferDescriptor {
                                        label: Some("NDI Readback"),
                                        size: buffer_size,
                                        usage: wgpu::BufferUsages::COPY_DST
                                            | wgpu::BufferUsages::MAP_READ,
                                        mapped_at_creation: false,
                                    });
                                (buffer, std::sync::Arc::new(AtomicBool::new(false)))
                            })
                            .clone();

                        app.backend.queue.submit(std::iter::once(offscreen_encoder.finish()));

                        // Check if previous readback is ready
                        let _ = app.backend.device.poll(wgpu::PollType::Wait {
                            submission_index: None,
                            timeout: Some(std::time::Duration::from_millis(0)),
                        });

                        if mapping_requested.load(Ordering::SeqCst) {
                            if let Some(buf_data) = app.ndi_readbacks.get(&part_id) {
                                let (buf, _) = buf_data;
                                if !buf.slice(..).get_mapped_range().is_empty() {
                                    let view = buf.slice(..).get_mapped_range();
                                    let frame_data = view.to_vec();

                                    let video_frame = vorce_io::format::VideoFrame {
                                        data: vorce_io::format::FrameData::Cpu(Arc::new(
                                            frame_data,
                                        )),
                                        format: vorce_io::format::VideoFormat {
                                            width,
                                            height,
                                            pixel_format: vorce_io::format::PixelFormat::BGRA8,
                                            frame_rate: 60.0,
                                        },
                                        timestamp: std::time::Duration::from_secs(0),
                                        metadata: Default::default(),
                                    };

                                    if let Err(e) = sender.send_frame(&video_frame) {
                                        tracing::warn!("Failed to send NDI frame: {}", e);
                                    }
                                    buf.unmap();
                                    mapping_requested.store(false, Ordering::SeqCst);
                                }
                            }
                        }

                        // Queue new readback
                        let mut new_encoder = app.backend.device.create_command_encoder(
                            &wgpu::CommandEncoderDescriptor { label: Some("NDI Readback Encoder") },
                        );
                        new_encoder.copy_texture_to_buffer(
                            wgpu::TexelCopyTextureInfo {
                                texture: &texture,
                                mip_level: 0,
                                origin: wgpu::Origin3d::ZERO,
                                aspect: wgpu::TextureAspect::All,
                            },
                            wgpu::TexelCopyBufferInfo {
                                buffer: &buffer,
                                layout: wgpu::TexelCopyBufferLayout {
                                    offset: 0,
                                    bytes_per_row: Some(bytes_per_row),
                                    rows_per_image: Some(height),
                                },
                            },
                            wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
                        );
                        app.backend.queue.submit(std::iter::once(new_encoder.finish()));

                        let slice = buffer.slice(..);
                        let requested_clone = mapping_requested.clone();
                        slice.map_async(wgpu::MapMode::Read, move |res| {
                            if res.is_ok() {
                                requested_clone.store(true, Ordering::SeqCst);
                            }
                        });
                    }
                }
            }
        }
    }
    if output_id == 0 {
        app.frame_counter = app.frame_counter.saturating_add(1);
    }

    Ok(())
}
