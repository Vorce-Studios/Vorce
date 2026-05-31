use crate::oscillator_renderer::resources::OscillatorResources;
use crate::oscillator_renderer::vertex::Vertex;
use std::sync::Arc;

pub(crate) struct OscillatorPipelines {
    pub simulation_pipeline: wgpu::RenderPipeline,
    pub distortion_pipeline: wgpu::RenderPipeline,
}

impl OscillatorPipelines {
    pub(crate) fn new(
        device: &Arc<wgpu::Device>,
        target_format: wgpu::TextureFormat,
        resources: &OscillatorResources,
    ) -> Self {
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
            bind_group_layouts: &[
                Some(&resources.sim_texture_layout),
                Some(&resources.sim_uniform_layout),
            ],
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
            bind_group_layouts: &[
                Some(&resources.dist_texture_layout),
                Some(&resources.dist_uniform_layout),
            ],
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

        Self { simulation_pipeline, distortion_pipeline }
    }
}
