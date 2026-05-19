use std::sync::Arc;
use wgpu::util::DeviceExt;

pub struct OscillatorResources {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pub non_filtering_sampler: wgpu::Sampler,
    pub sampler: wgpu::Sampler,
    pub vertex_buffer: wgpu::Buffer,
    pub index_buffer: wgpu::Buffer,
}

impl OscillatorResources {
    pub fn new(device: Arc<wgpu::Device>, queue: Arc<wgpu::Queue>) -> Self {
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

        let vertex_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Oscillator Vertex Buffer"),
            contents: bytemuck::cast_slice(super::types::QUAD_VERTICES),
            usage: wgpu::BufferUsages::VERTEX,
        });

        let index_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Oscillator Index Buffer"),
            contents: bytemuck::cast_slice(super::types::QUAD_INDICES),
            usage: wgpu::BufferUsages::INDEX,
        });

        Self { device, queue, non_filtering_sampler, sampler, vertex_buffer, index_buffer }
    }
}
