//! Oscillator rendering and simulation module

mod distortion;
mod simulation;
mod types;

use crate::Result;
use std::sync::Arc;
use tracing::info;
use vorce_core::{OscillatorConfig, PhaseInitMode};

use self::distortion::OscillatorDistortion;
use self::simulation::OscillatorSimulation;

/// Oscillator distortion renderer
pub struct OscillatorRenderer {
    simulation: OscillatorSimulation,
    distortion: OscillatorDistortion,
    time_elapsed: f32,
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

        let simulation = OscillatorSimulation::new(device.clone(), queue.clone(), config)?;
        let distortion =
            OscillatorDistortion::new(device, queue, target_format, config, sim_width, sim_height)?;

        Ok(Self { simulation, distortion, time_elapsed: 0.0 })
    }

    /// Initialize phase texture with a specific pattern
    pub fn initialize_phases(&mut self, mode: PhaseInitMode) {
        self.simulation.initialize_phases(mode);
    }

    /// Update simulation for one timestep
    pub fn update(&mut self, delta_time: f32, config: &OscillatorConfig) {
        self.time_elapsed += delta_time;
        self.simulation.update(delta_time, self.time_elapsed, config);
    }

    /// Render distortion effect to output
    pub fn render(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        input_view: &wgpu::TextureView,
        output_view: &wgpu::TextureView,
        width: u32,
        height: u32,
        config: &OscillatorConfig,
    ) {
        let phase_view = if self.simulation.current_phase {
            &self.simulation.phase_view_b
        } else {
            &self.simulation.phase_view_a
        };

        self.distortion.render(
            encoder,
            input_view,
            output_view,
            phase_view,
            width,
            height,
            self.simulation.sim_width,
            self.simulation.sim_height,
            self.time_elapsed,
            config,
        );
    }
}
