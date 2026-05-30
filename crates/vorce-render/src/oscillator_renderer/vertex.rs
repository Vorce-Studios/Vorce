use bytemuck::{Pod, Zeroable};

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
