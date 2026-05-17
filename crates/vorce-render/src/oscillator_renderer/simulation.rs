use crate::Result;
use std::sync::Arc;
use vorce_core::{OscillatorConfig, PhaseInitMode};
use wgpu::util::DeviceExt;

use super::types::{SimulationParams, Vertex, QUAD_INDICES, QUAD_VERTICES};

pub struct OscillatorSimulation {
    pipeline: wgpu::RenderPipeline,

    // Bind group layouts
    _texture_layout: wgpu::BindGroupLayout,
    _uniform_layout: wgpu::BindGroupLayout,

    // Phase textures (ping-pong)
    phase_texture_a: wgpu::Texture,
    pub phase_view_a: wgpu::TextureView,
    phase_texture_b: wgpu::Texture,
    pub phase_view_b: wgpu::TextureView,

    // Framebuffers
    fbo_a: wgpu::TextureView,
    fbo_b: wgpu::TextureView,

    // Buffers
    vertex_buffer: wgpu::Buffer,
    index_buffer: wgpu::Buffer,
    uniform_buffer: wgpu::Buffer,

    // Bind groups
    bind_group_a: wgpu::BindGroup,
    bind_group_b: wgpu::BindGroup,
    uniform_bind_group: wgpu::BindGroup,

    // Sampler
    _non_filtering_sampler: wgpu::Sampler,

    // State
    pub sim_width: u32,
    pub sim_height: u32,
    pub current_phase: bool, // false = A, true = B

    // Device reference
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
}

impl OscillatorSimulation {
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        config: &OscillatorConfig,
    ) -> Result<Self> {
        let (sim_width, sim_height) = config.simulation_resolution.dimensions();

        let non_filtering_sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Oscillator Non-Filtering Sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Nearest,
            min_filter: wgpu::FilterMode::Nearest,
            mipmap_filter: wgpu::MipmapFilterMode::Nearest,
            ..Default::default()
        });

        let phase_texture_a =
            Self::create_phase_texture(&device, sim_width, sim_height, "Phase Texture A");
        let phase_view_a = phase_texture_a.create_view(&wgpu::TextureViewDescriptor::default());
        let fbo_a = phase_texture_a.create_view(&wgpu::TextureViewDescriptor::default());

        let phase_texture_b =
            Self::create_phase_texture(&device, sim_width, sim_height, "Phase Texture B");
        let phase_view_b = phase_texture_b.create_view(&wgpu::TextureViewDescriptor::default());
        let fbo_b = phase_texture_b.create_view(&wgpu::TextureViewDescriptor::default());

        let texture_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Sim Texture Bind Group Layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::NonFiltering),
                    count: None,
                },
            ],
        });

        let uniform_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Sim Uniform Bind Group Layout"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });

        let shader_source = include_str!("../../../../shaders/oscillator_simulation.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Oscillator Simulation Shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Sim Pipeline Layout"),
            bind_group_layouts: &[Some(&texture_layout), Some(&uniform_layout)],
            immediate_size: 0,
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Simulation Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: &[Vertex::desc()],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: wgpu::TextureFormat::R32Float,
                    blend: None,
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                unclipped_depth: false,
                polygon_mode: wgpu::PolygonMode::Fill,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState {
                count: 1,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview_mask: None,
            cache: None,
        });

        let vertex_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Oscillator Vertex Buffer"),
            contents: bytemuck::cast_slice(QUAD_VERTICES),
            usage: wgpu::BufferUsages::VERTEX,
        });

        let index_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Oscillator Index Buffer"),
            contents: bytemuck::cast_slice(QUAD_INDICES),
            usage: wgpu::BufferUsages::INDEX,
        });

        let sim_params = Self::create_sim_params(config, sim_width, sim_height, 0.0, 0.016);
        let uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Sim Uniform Buffer"),
            contents: bytemuck::cast_slice(&[sim_params]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let bind_group_a = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Sim Bind Group A"),
            layout: &texture_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&phase_view_a),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&non_filtering_sampler),
                },
            ],
        });

        let bind_group_b = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Sim Bind Group B"),
            layout: &texture_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&phase_view_b),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&non_filtering_sampler),
                },
            ],
        });

        let uniform_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Sim Uniform Bind Group"),
            layout: &uniform_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buffer.as_entire_binding(),
            }],
        });

        Ok(Self {
            pipeline,
            _texture_layout: texture_layout,
            _uniform_layout: uniform_layout,
            phase_texture_a,
            phase_view_a,
            phase_texture_b,
            phase_view_b,
            fbo_a,
            fbo_b,
            vertex_buffer,
            index_buffer,
            uniform_buffer,
            bind_group_a,
            bind_group_b,
            uniform_bind_group,
            _non_filtering_sampler: non_filtering_sampler,
            sim_width,
            sim_height,
            current_phase: false,
            device,
            queue,
        })
    }

    fn create_phase_texture(
        device: &wgpu::Device,
        width: u32,
        height: u32,
        label: &str,
    ) -> wgpu::Texture {
        device.create_texture(&wgpu::TextureDescriptor {
            label: Some(label),
            size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R32Float,
            usage: wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::RENDER_ATTACHMENT
                | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        })
    }

    pub fn initialize_phases(&mut self, mode: PhaseInitMode) {
        tracing::debug!("Initializing phases with mode: {:?}", mode);

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
            PhaseInitMode::Uniform => {}
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

        self.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.phase_texture_a,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            bytemuck::cast_slice(&phase_data),
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(self.sim_width * 4),
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
                texture: &self.phase_texture_b,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            bytemuck::cast_slice(&phase_data),
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(self.sim_width * 4),
                rows_per_image: Some(self.sim_height),
            },
            wgpu::Extent3d {
                width: self.sim_width,
                height: self.sim_height,
                depth_or_array_layers: 1,
            },
        );
    }

    fn create_sim_params(
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

    pub fn update(&mut self, delta_time: f32, time_elapsed: f32, config: &OscillatorConfig) {
        let sim_params = Self::create_sim_params(
            config,
            self.sim_width,
            self.sim_height,
            time_elapsed,
            delta_time,
        );
        self.queue.write_buffer(&self.uniform_buffer, 0, bytemuck::cast_slice(&[sim_params]));

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Oscillator Simulation Encoder"),
        });

        let (input_bind_group, output_view) = if self.current_phase {
            (&self.bind_group_b, &self.fbo_a)
        } else {
            (&self.bind_group_a, &self.fbo_b)
        };

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

            render_pass.set_pipeline(&self.pipeline);
            render_pass.set_bind_group(0, input_bind_group, &[]);
            render_pass.set_bind_group(1, &self.uniform_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
            render_pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..6, 0, 0..1);
        }

        self.queue.submit(std::iter::once(encoder.finish()));

        self.current_phase = !self.current_phase;
    }
}
