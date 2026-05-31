//! Oscillator Distortion Renderer
//!
//! Implements Kuramoto-based coupled oscillator simulation for dynamic distortion effects

pub(crate) mod params;
pub(crate) mod pipelines;
pub(crate) mod resources;
pub(crate) mod vertex;

use crate::Result;
use std::sync::Arc;
use tracing::{debug, info};
use vorce_core::{OscillatorConfig, PhaseInitMode};

use params::{DistortionParams, SimulationParams};
use pipelines::OscillatorPipelines;
use resources::OscillatorResources;

/// Oscillator distortion renderer
pub struct OscillatorRenderer {
    pipelines: OscillatorPipelines,
    resources: OscillatorResources,

    // State
    sim_width: u32,
    sim_height: u32,
    current_phase: bool, // false = A, true = B
    time_elapsed: f32,

    // Device reference
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
}

impl OscillatorRenderer {
    /// Create a new oscillator renderer
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
        config: &OscillatorConfig,
    ) -> Result<Self> {
        info!("Creating oscillator renderer");

        let (sim_width, sim_height) = config.simulation_resolution.dimensions();

        let resources = OscillatorResources::new(&device, sim_width, sim_height, config);
        let pipelines = OscillatorPipelines::new(&device, target_format, &resources);

        Ok(Self {
            pipelines,
            resources,
            sim_width,
            sim_height,
            current_phase: false,
            time_elapsed: 0.0,
            device,
            queue,
        })
    }

    /// Initialize phase texture with a specific pattern
    pub fn initialize_phases(&mut self, mode: PhaseInitMode) {
        debug!("Initializing phases with mode: {:?}", mode);

        let size = (self.sim_width * self.sim_height) as usize;
        let mut phase_data = vec![0.0f32; size];

        match mode {
            PhaseInitMode::Random => {
                use rand::RngExt;
                let mut rng = rand::rng();
                for phase in &mut phase_data {
                    *phase = rng.random::<f32>() * 2.0 * std::f32::consts::PI;
                }
            }
            PhaseInitMode::Uniform => {
                // All zeros (already initialized)
            }
            PhaseInitMode::PlaneHorizontal => {
                for y in 0..self.sim_height {
                    for x in 0..self.sim_width {
                        let u = x as f32 / self.sim_width as f32;
                        let idx = (y * self.sim_width + x) as usize;
                        phase_data[idx] = u * 2.0 * std::f32::consts::PI;
                    }
                }
            }
            PhaseInitMode::PlaneVertical => {
                for y in 0..self.sim_height {
                    for x in 0..self.sim_width {
                        let v = y as f32 / self.sim_height as f32;
                        let idx = (y * self.sim_width + x) as usize;
                        phase_data[idx] = v * 2.0 * std::f32::consts::PI;
                    }
                }
            }
            PhaseInitMode::PlaneDiagonal => {
                for y in 0..self.sim_height {
                    for x in 0..self.sim_width {
                        let u = x as f32 / self.sim_width as f32;
                        let v = y as f32 / self.sim_height as f32;
                        let idx = (y * self.sim_width + x) as usize;
                        phase_data[idx] = (u + v) * std::f32::consts::PI;
                    }
                }
            }
        }

        // Upload to both textures
        let bytes: &[u8] = bytemuck::cast_slice(&phase_data);

        let bytes_per_row = self.sim_width * 4;

        self.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.resources.phase_texture_a,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            bytes,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: Some(self.sim_height),
            },
            wgpu::Extent3d {
                width: self.sim_width,
                height: self.sim_height,
                depth_or_array_layers: 1,
            },
        );

        self.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.resources.phase_texture_b,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            bytes,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: Some(self.sim_height),
            },
            wgpu::Extent3d {
                width: self.sim_width,
                height: self.sim_height,
                depth_or_array_layers: 1,
            },
        );
    }

    /// Update simulation state
    pub fn update(&mut self, delta_time: f32, config: &OscillatorConfig) {
        // Accumulate time internally
        self.time_elapsed += delta_time;

        let sim_params = crate::oscillator_renderer::create_sim_params(
            config,
            self.sim_width,
            self.sim_height,
            self.time_elapsed,
            delta_time,
        );

        // Upload to uniform buffer
        self.queue.write_buffer(
            &self.resources.sim_uniform_buffer,
            0,
            bytemuck::cast_slice(&[sim_params]),
        );

        // Run simulation step
        self.run_simulation_step();
    }

    fn run_simulation_step(&mut self) {
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Oscillator Simulation Encoder"),
        });

        // Determine input/output based on current phase
        let (input_bind_group, output_view) = if self.current_phase {
            (&self.resources.sim_bind_group_b, &self.resources.sim_fbo_a)
        } else {
            (&self.resources.sim_bind_group_a, &self.resources.sim_fbo_b)
        };

        // Run simulation pass
        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Oscillator Simulation Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    depth_slice: None,
                    view: output_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
                multiview_mask: None,
            });

            render_pass.set_pipeline(&self.pipelines.simulation_pipeline);
            render_pass.set_bind_group(0, input_bind_group, &[]);
            render_pass.set_bind_group(1, &self.resources.sim_uniform_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.resources.vertex_buffer.slice(..));
            render_pass
                .set_index_buffer(self.resources.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..6, 0, 0..1);
        }

        self.queue.submit(std::iter::once(encoder.finish()));

        // Swap phase textures
        self.current_phase = !self.current_phase;
    }

    /// Render distortion effect to output
    pub fn render(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        input_view: &wgpu::TextureView,
        output_view: &wgpu::TextureView,
        width: u32,
        height: u32,
        config: &OscillatorConfig,
    ) {
        // Update distortion uniforms
        let dist_params = crate::oscillator_renderer::create_dist_params(
            config,
            width,
            height,
            self.sim_width,
            self.sim_height,
            self.time_elapsed,
        );
        self.queue.write_buffer(
            &self.resources.dist_uniform_buffer,
            0,
            bytemuck::cast_slice(&[dist_params]),
        );

        // Get current phase texture
        let phase_view = if self.current_phase {
            &self.resources.phase_view_b
        } else {
            &self.resources.phase_view_a
        };

        // Create bind group for distortion (input texture + phase texture)
        let dist_bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Dist Bind Group"),
            layout: &self.resources.dist_texture_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(input_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&self.resources.sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(phase_view),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::Sampler(&self.resources.non_filtering_sampler),
                },
            ],
        });

        // Render distortion pass
        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Oscillator Distortion Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    depth_slice: None,
                    view: output_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
                multiview_mask: None,
            });

            render_pass.set_pipeline(&self.pipelines.distortion_pipeline);
            render_pass.set_bind_group(0, &dist_bind_group, &[]);
            render_pass.set_bind_group(1, &self.resources.dist_uniform_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.resources.vertex_buffer.slice(..));
            render_pass
                .set_index_buffer(self.resources.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..6, 0, 0..1);
        }
    }
}

pub(crate) fn create_sim_params(
    config: &OscillatorConfig,
    sim_width: u32,
    sim_height: u32,
    time: f32,
    delta_time: f32,
) -> SimulationParams {
    SimulationParams {
        sim_resolution: [sim_width as f32, sim_height as f32],
        delta_time,
        kernel_radius: config.kernel_radius,
        frequency_min: config.frequency_min,
        frequency_max: config.frequency_max,
        time,
        kernel_shrink: 1.0,
        ring_distances: [
            config.rings[0].distance,
            config.rings[1].distance,
            config.rings[2].distance,
            config.rings[3].distance,
        ],
        ring_widths: [
            config.rings[0].width,
            config.rings[1].width,
            config.rings[2].width,
            config.rings[3].width,
        ],
        ring_couplings: [
            config.rings[0].coupling,
            config.rings[1].coupling,
            config.rings[2].coupling,
            config.rings[3].coupling,
        ],
        noise_amount: config.noise_amount,
        use_log_polar: match config.coordinate_mode {
            vorce_core::CoordinateMode::LogPolar => 1,
            _ => 0,
        },
        _padding: [0.0; 2],
    }
}

pub(crate) fn create_dist_params(
    config: &OscillatorConfig,
    width: u32,
    height: u32,
    sim_width: u32,
    sim_height: u32,
    time: f32,
) -> DistortionParams {
    DistortionParams {
        resolution: [width as f32, height as f32],
        sim_resolution: [sim_width as f32, sim_height as f32],
        distortion_amount: config.distortion_amount,
        distortion_scale: config.distortion_scale,
        distortion_speed: config.distortion_speed,
        overlay_opacity: config.overlay_opacity,
        time,
        color_mode: config.color_mode.to_u32(),
        use_log_polar: match config.coordinate_mode {
            vorce_core::CoordinateMode::LogPolar => 1,
            _ => 0,
        },
        _padding: 0.0,
    }
}
