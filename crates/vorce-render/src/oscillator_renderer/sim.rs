use vorce_core::OscillatorConfig;

use super::params::SimulationParams;
use super::state::OscillatorRenderer;

impl OscillatorRenderer {
    /// Update simulation state
    pub fn update(&mut self, delta_time: f32, config: &OscillatorConfig) {
        // Accumulate time internally
        self.time_elapsed += delta_time;

        let sim_params = create_sim_params(
            config,
            self.sim_width,
            self.sim_height,
            self.time_elapsed,
            delta_time,
        );

        // Upload to uniform buffer
        self.queue.write_buffer(
            &self.resources.sim_uniform_buffer,
            0,
            bytemuck::cast_slice(&[sim_params]),
        );

        // Run simulation step
        self.run_simulation_step();
    }

    fn run_simulation_step(&mut self) {
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Oscillator Simulation Encoder"),
        });

        // Determine input/output based on current phase
        let (input_bind_group, output_view) = if self.current_phase {
            (&self.resources.sim_bind_group_b, &self.resources.sim_fbo_a)
        } else {
            (&self.resources.sim_bind_group_a, &self.resources.sim_fbo_b)
        };

        // Run simulation pass
        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Oscillator Simulation Pass"),
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

            render_pass.set_pipeline(&self.pipelines.simulation_pipeline);
            render_pass.set_bind_group(0, input_bind_group, &[]);
            render_pass.set_bind_group(1, &self.resources.sim_uniform_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.resources.vertex_buffer.slice(..));
            render_pass
                .set_index_buffer(self.resources.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..6, 0, 0..1);
        }

        self.queue.submit(std::iter::once(encoder.finish()));

        // Swap phase textures
        self.current_phase = !self.current_phase;
    }
}

pub(crate) fn create_sim_params(
    config: &OscillatorConfig,
    sim_width: u32,
    sim_height: u32,
    time: f32,
    delta_time: f32,
) -> SimulationParams {
    SimulationParams {
        sim_resolution: [sim_width as f32, sim_height as f32],
        delta_time,
        kernel_radius: config.kernel_radius,
        frequency_min: config.frequency_min,
        frequency_max: config.frequency_max,
        time,
        kernel_shrink: 1.0,
        ring_distances: [
            config.rings[0].distance,
            config.rings[1].distance,
            config.rings[2].distance,
            config.rings[3].distance,
        ],
        ring_widths: [
            config.rings[0].width,
            config.rings[1].width,
            config.rings[2].width,
            config.rings[3].width,
        ],
        ring_couplings: [
            config.rings[0].coupling,
            config.rings[1].coupling,
            config.rings[2].coupling,
            config.rings[3].coupling,
        ],
        noise_amount: config.noise_amount,
        use_log_polar: match config.coordinate_mode {
            vorce_core::CoordinateMode::LogPolar => 1,
            _ => 0,
        },
        _padding: [0.0; 2],
    }
}
