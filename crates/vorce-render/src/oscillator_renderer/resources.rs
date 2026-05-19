use std::sync::Arc;

pub struct OscillatorResources {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,

    pub simulation_pipeline: wgpu::RenderPipeline,
    pub distortion_pipeline: wgpu::RenderPipeline,

    pub sim_texture_layout: wgpu::BindGroupLayout,
    pub sim_uniform_layout: wgpu::BindGroupLayout,
    pub dist_texture_layout: wgpu::BindGroupLayout,
    pub dist_uniform_layout: wgpu::BindGroupLayout,

    pub phase_texture_a: wgpu::Texture,
    pub phase_view_a: wgpu::TextureView,
    pub phase_texture_b: wgpu::Texture,
    pub phase_view_b: wgpu::TextureView,

    pub sim_fbo_a: wgpu::TextureView,
    pub sim_fbo_b: wgpu::TextureView,

    pub vertex_buffer: wgpu::Buffer,
    pub index_buffer: wgpu::Buffer,
    pub sim_uniform_buffer: wgpu::Buffer,
    pub dist_uniform_buffer: wgpu::Buffer,

    pub sim_bind_group_a: wgpu::BindGroup,
    pub sim_bind_group_b: wgpu::BindGroup,
    pub sim_uniform_bind_group: wgpu::BindGroup,
    pub dist_uniform_bind_group: wgpu::BindGroup,

    pub sampler: wgpu::Sampler,
    pub non_filtering_sampler: wgpu::Sampler,
}
