use std::sync::Arc;
use vorce_core::OscillatorConfig;
use wgpu::util::DeviceExt;

use crate::oscillator_renderer::vertex::{QUAD_INDICES, QUAD_VERTICES};

pub(crate) struct OscillatorResources {
    // Bind group layouts
    pub sim_texture_layout: wgpu::BindGroupLayout,
    pub sim_uniform_layout: wgpu::BindGroupLayout,
    pub dist_texture_layout: wgpu::BindGroupLayout,
    pub dist_uniform_layout: wgpu::BindGroupLayout,

    // Phase textures (ping-pong)
    pub phase_texture_a: wgpu::Texture,
    pub phase_view_a: wgpu::TextureView,
    pub phase_texture_b: wgpu::Texture,
    pub phase_view_b: wgpu::TextureView,

    // Framebuffers for simulation
    pub sim_fbo_a: wgpu::TextureView,
    pub sim_fbo_b: wgpu::TextureView,

    // Buffers
    pub vertex_buffer: wgpu::Buffer,
    pub index_buffer: wgpu::Buffer,
    pub sim_uniform_buffer: wgpu::Buffer,
    pub dist_uniform_buffer: wgpu::Buffer,

    // Bind groups
    pub sim_bind_group_a: wgpu::BindGroup,
    pub sim_bind_group_b: wgpu::BindGroup,
    pub sim_uniform_bind_group: wgpu::BindGroup,
    pub dist_uniform_bind_group: wgpu::BindGroup,

    // Samplers
    pub sampler: wgpu::Sampler,
    pub non_filtering_sampler: wgpu::Sampler,
}

impl OscillatorResources {
    pub(crate) fn new(
        device: &Arc<wgpu::Device>,
        sim_width: u32,
        sim_height: u32,
        config: &OscillatorConfig,
    ) -> Self {
        // Create samplers
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

        // Phase textures
        let phase_texture_a =
            Self::create_phase_texture(device, sim_width, sim_height, "Phase Texture A");
        let phase_view_a = phase_texture_a.create_view(&wgpu::TextureViewDescriptor::default());
        let sim_fbo_a = phase_texture_a.create_view(&wgpu::TextureViewDescriptor::default());

        let phase_texture_b =
            Self::create_phase_texture(device, sim_width, sim_height, "Phase Texture B");
        let phase_view_b = phase_texture_b.create_view(&wgpu::TextureViewDescriptor::default());
        let sim_fbo_b = phase_texture_b.create_view(&wgpu::TextureViewDescriptor::default());

        // Bind group layouts
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

        // Buffers
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

        let sim_params = crate::oscillator_renderer::sim::create_sim_params(
            config, sim_width, sim_height, 0.0, 0.016,
        );
        let sim_uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Sim Uniform Buffer"),
            contents: bytemuck::cast_slice(&[sim_params]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let dist_params = crate::oscillator_renderer::render::create_dist_params(
            config, 1920, 1080, sim_width, sim_height, 0.0,
        );
        let dist_uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Dist Uniform Buffer"),
            contents: bytemuck::cast_slice(&[dist_params]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        // Bind groups
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

        Self {
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
            vertex_buffer,
            index_buffer,
            sim_uniform_buffer,
            dist_uniform_buffer,
            sim_bind_group_a,
            sim_bind_group_b,
            sim_uniform_bind_group,
            dist_uniform_bind_group,
            sampler,
            non_filtering_sampler,
        }
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
}
