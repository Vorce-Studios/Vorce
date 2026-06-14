use tracing::debug;
use vorce_core::PhaseInitMode;

use super::state::OscillatorRenderer;

impl OscillatorRenderer {
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
}
