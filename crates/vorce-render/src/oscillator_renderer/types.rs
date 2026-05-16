use bytemuck::{Pod, Zeroable};

/// Simulation uniform parameters
#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
pub(crate) struct SimulationParams {
    pub sim_resolution: [f32; 2],
    pub delta_time: f32,
    pub kernel_radius: f32,

    pub frequency_min: f32,
    pub frequency_max: f32,
    pub time: f32,
    pub kernel_shrink: f32,

    // Ring parameters (4 rings)
    pub ring_distances: [f32; 4],
    pub ring_widths: [f32; 4],
    pub ring_couplings: [f32; 4],

    pub noise_amount: f32,
    pub use_log_polar: u32,
    pub _padding: [f32; 2],
}

/// Distortion uniform parameters
#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
pub(crate) struct DistortionParams {
    pub resolution: [f32; 2],
    pub sim_resolution: [f32; 2],

    pub distortion_amount: f32,
    pub distortion_scale: f32,
    pub distortion_speed: f32,
    pub overlay_opacity: f32,

    pub time: f32,
    pub color_mode: u32,
    pub use_log_polar: u32,
    pub _padding: f32,
}

/// Fullscreen quad vertex
#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
pub(crate) struct Vertex {
    pub position: [f32; 2],
    pub texcoord: [f32; 2],
}

impl Vertex {
    pub(crate) fn desc() -> wgpu::VertexBufferLayout<'static> {
        wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<Vertex>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &[
                wgpu::VertexAttribute {
                    offset: 0,
                    shader_location: 0,
                    format: wgpu::VertexFormat::Float32x2,
                },
                wgpu::VertexAttribute {
                    offset: std::mem::size_of::<[f32; 2]>() as wgpu::BufferAddress,
                    shader_location: 1,
                    format: wgpu::VertexFormat::Float32x2,
                },
            ],
        }
    }
}

// Fullscreen quad vertices
pub(crate) const QUAD_VERTICES: &[Vertex] = &[
    Vertex { position: [-1.0, -1.0], texcoord: [0.0, 1.0] },
    Vertex { position: [1.0, -1.0], texcoord: [1.0, 1.0] },
    Vertex { position: [1.0, 1.0], texcoord: [1.0, 0.0] },
    Vertex { position: [-1.0, 1.0], texcoord: [0.0, 0.0] },
];

pub(crate) const QUAD_INDICES: &[u16] = &[0, 1, 2, 0, 2, 3];
