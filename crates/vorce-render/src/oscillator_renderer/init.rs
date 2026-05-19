use super::resources::OscillatorResources;
use super::types::*;
use super::OscillatorRenderer;
use crate::Result;
use std::sync::Arc;
use tracing::{debug, info};
use vorce_core::{OscillatorConfig, PhaseInitMode};
use wgpu::util::DeviceExt;

impl OscillatorRenderer {
    pub(crate) fn init(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
        config: &OscillatorConfig,
    ) -> Result<Self> {
        info!("Creating oscillator renderer");

        let (sim_width, sim_height) = config.simulation_resolution.dimensions();

        // Create sampler
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Oscillator Sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::MipmapFilterMode::Linear,
            ..Default::default()
        });

        // Create non-filtering sampler for R32Float textures
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

        // Create phase textures (ping-pong)
        let phase_texture_a =
            Self::create_phase_texture(&device, sim_width, sim_height, "Phase Texture A");
        let phase_view_a = phase_texture_a.create_view(&wgpu::TextureViewDescriptor::default());
        let sim_fbo_a = phase_texture_a.create_view(&wgpu::TextureViewDescriptor::default());

        let phase_texture_b =
            Self::create_phase_texture(&device, sim_width, sim_height, "Phase Texture B");
        let phase_view_b = phase_texture_b.create_view(&wgpu::TextureViewDescriptor::default());
        let sim_fbo_b = phase_texture_b.create_view(&wgpu::TextureViewDescriptor::default());

        // Create bind group layouts for simulation
        let sim_texture_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
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

        let sim_uniform_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
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

        // Create bind group layouts for distortion
        let dist_texture_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Dist Texture Bind Group Layout"),
                entries: &[
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 2,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            sample_type: wgpu::TextureSampleType::Float { filterable: false },
                            view_dimension: wgpu::TextureViewDimension::D2,
                            multisampled: false,
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 3,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::NonFiltering),
                        count: None,
                    },
                ],
            });

        let dist_uniform_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Dist Uniform Bind Group Layout"),
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

        // Load shaders
        let sim_shader_source = include_str!("../../../../shaders/oscillator_simulation.wgsl");
        let sim_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Oscillator Simulation Shader"),
            source: wgpu::ShaderSource::Wgsl(sim_shader_source.into()),
        });

        let dist_shader_source = include_str!("../../../../shaders/oscillator_distortion.wgsl");
        let dist_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Oscillator Distortion Shader"),
            source: wgpu::ShaderSource::Wgsl(dist_shader_source.into()),
        });

        // Create simulation pipeline
        let sim_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Sim Pipeline Layout"),
            bind_group_layouts: &[Some(&sim_texture_layout), Some(&sim_uniform_layout)],
            immediate_size: 0,
        });

        let simulation_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Simulation Pipeline"),
            layout: Some(&sim_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &sim_shader,
                entry_point: Some("vs_main"),
                buffers: &[Vertex::desc()],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &sim_shader,
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

        // Create distortion pipeline
        let dist_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Dist Pipeline Layout"),
            bind_group_layouts: &[Some(&dist_texture_layout), Some(&dist_uniform_layout)],
            immediate_size: 0,
        });

        let distortion_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Distortion Pipeline"),
            layout: Some(&dist_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &dist_shader,
                entry_point: Some("vs_main"),
                buffers: &[Vertex::desc()],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &dist_shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
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

        // Create vertex and index buffers
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

        // Create uniform buffers
        let sim_params = Self::create_sim_params(config, sim_width, sim_height, 0.0, 0.016);
        let sim_uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Sim Uniform Buffer"),
            contents: bytemuck::cast_slice(&[sim_params]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let dist_params = Self::create_dist_params(config, 1920, 1080, sim_width, sim_height, 0.0);
        let dist_uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Dist Uniform Buffer"),
            contents: bytemuck::cast_slice(&[dist_params]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        // Create bind groups for simulation (ping-pong)
        let sim_bind_group_a = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Sim Bind Group A"),
            layout: &sim_texture_layout,
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

        let sim_bind_group_b = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Sim Bind Group B"),
            layout: &sim_texture_layout,
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

        let sim_uniform_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Sim Uniform Bind Group"),
            layout: &sim_uniform_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: sim_uniform_buffer.as_entire_binding(),
            }],
        });

        let dist_uniform_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Dist Uniform Bind Group"),
            layout: &dist_uniform_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: dist_uniform_buffer.as_entire_binding(),
            }],
        });

        Ok(Self {
            resources: OscillatorResources {
                simulation_pipeline,
                distortion_pipeline,
                sim_texture_layout,
                sim_uniform_layout,
                dist_texture_layout,
                dist_uniform_layout,
                phase_texture_a,
                phase_view_a,
                phase_texture_b,
                phase_view_b,
                sim_fbo_a,
                sim_fbo_b,
                sim_uniform_buffer,
                dist_uniform_buffer,
                sim_bind_group_a,
                sim_bind_group_b,
                sim_uniform_bind_group,
                dist_uniform_bind_group,
                sampler,
                non_filtering_sampler,
                vertex_buffer,
                index_buffer,
                device,
                queue,
            },
            sim_width,
            sim_height,
            current_phase: false,
            time_elapsed: 0.0,
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

        // Upload to both phase textures
        self.resources.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.resources.phase_texture_a,
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

        self.resources.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.resources.phase_texture_b,
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
}
