use crate::Result;
use std::sync::Arc;
use vorce_core::OscillatorConfig;
use wgpu::util::DeviceExt;

use super::types::{DistortionParams, Vertex};

pub struct OscillatorDistortion {
    pipeline: wgpu::RenderPipeline,

    // Bind group layouts
    texture_layout: wgpu::BindGroupLayout,
    _uniform_layout: wgpu::BindGroupLayout,

    // Buffers
    uniform_buffer: wgpu::Buffer,

    // Bind groups
    uniform_bind_group: wgpu::BindGroup,

    // Resources
    resources: Arc<crate::oscillator_renderer::resources::OscillatorResources>,
}

impl OscillatorDistortion {
    pub fn new(
        resources: Arc<crate::oscillator_renderer::resources::OscillatorResources>,
        target_format: wgpu::TextureFormat,
        config: &OscillatorConfig,
        sim_width: u32,
        sim_height: u32,
    ) -> Result<Self> {
        let texture_layout =
            resources.device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
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

        let uniform_layout =
            resources.device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
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

        let shader_source = include_str!("../../../../shaders/oscillator_distortion.wgsl");
        let shader = resources.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Oscillator Distortion Shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let pipeline_layout =
            resources.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Dist Pipeline Layout"),
                bind_group_layouts: &[Some(&texture_layout), Some(&uniform_layout)],
                immediate_size: 0,
            });

        let pipeline = resources.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Distortion Pipeline"),
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

        let dist_params = Self::create_dist_params(config, 1920, 1080, sim_width, sim_height, 0.0);
        let uniform_buffer =
            resources.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Dist Uniform Buffer"),
                contents: bytemuck::cast_slice(&[dist_params]),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

        let uniform_bind_group = resources.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Dist Uniform Bind Group"),
            layout: &uniform_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buffer.as_entire_binding(),
            }],
        });

        Ok(Self {
            pipeline,
            texture_layout,
            _uniform_layout: uniform_layout,
            uniform_buffer,
            uniform_bind_group,
            resources,
        })
    }

    fn create_dist_params(
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

    #[allow(clippy::too_many_arguments)]
    pub fn render(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        input_view: &wgpu::TextureView,
        output_view: &wgpu::TextureView,
        phase_view: &wgpu::TextureView,
        width: u32,
        height: u32,
        sim_width: u32,
        sim_height: u32,
        time_elapsed: f32,
        config: &OscillatorConfig,
    ) {
        let dist_params =
            Self::create_dist_params(config, width, height, sim_width, sim_height, time_elapsed);
        self.resources.queue.write_buffer(
            &self.uniform_buffer,
            0,
            bytemuck::cast_slice(&[dist_params]),
        );

        let dist_bind_group = self.resources.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Dist Bind Group"),
            layout: &self.texture_layout,
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

            render_pass.set_pipeline(&self.pipeline);
            render_pass.set_bind_group(0, &dist_bind_group, &[]);
            render_pass.set_bind_group(1, &self.uniform_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.resources.vertex_buffer.slice(..));
            render_pass
                .set_index_buffer(self.resources.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..6, 0, 0..1);
        }
    }
}
