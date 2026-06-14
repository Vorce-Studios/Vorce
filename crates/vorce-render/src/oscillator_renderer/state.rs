use crate::Result;
use std::sync::Arc;
use tracing::info;
use vorce_core::OscillatorConfig;

use super::pipelines::OscillatorPipelines;
use super::resources::OscillatorResources;

/// Oscillator distortion renderer
pub struct OscillatorRenderer {
    pub(crate) pipelines: OscillatorPipelines,
    pub(crate) resources: OscillatorResources,

    // State
    pub(crate) sim_width: u32,
    pub(crate) sim_height: u32,
    pub(crate) current_phase: bool, // false = A, true = B
    pub(crate) time_elapsed: f32,

    // Device reference
    pub(crate) device: Arc<wgpu::Device>,
    pub(crate) queue: Arc<wgpu::Queue>,
}

impl OscillatorRenderer {
    /// Create a new oscillator renderer
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
        config: &OscillatorConfig,
    ) -> Result<Self> {
        info!("Creating oscillator renderer");

        let (sim_width, sim_height) = config.simulation_resolution.dimensions();

        let resources = OscillatorResources::new(&device, sim_width, sim_height, config);
        let pipelines = OscillatorPipelines::new(&device, target_format, &resources);

        Ok(Self {
            pipelines,
            resources,
            sim_width,
            sim_height,
            current_phase: false,
            time_elapsed: 0.0,
            device,
            queue,
        })
    }
}
