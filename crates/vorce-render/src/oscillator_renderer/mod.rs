//! Oscillator Distortion Renderer
//!
//! Implements Kuramoto-based coupled oscillator simulation for dynamic distortion effects

pub mod distortion;
mod init;
pub mod resources;
pub mod simulation;
pub mod types;

use crate::Result;
use resources::OscillatorResources;
use std::sync::Arc;
use vorce_core::OscillatorConfig;

/// Oscillator distortion renderer
pub struct OscillatorRenderer {
    pub resources: OscillatorResources,

    // State
    pub sim_width: u32,
    pub sim_height: u32,
    pub current_phase: bool, // false = A, true = B
    pub time_elapsed: f32,
}

impl OscillatorRenderer {
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
        config: &OscillatorConfig,
    ) -> Result<Self> {
        Self::init(device, queue, target_format, config)
    }
}
