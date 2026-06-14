use vorce_core::OscillatorConfig;

use super::params::DistortionParams;
use super::state::OscillatorRenderer;

impl OscillatorRenderer {
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
        // Update distortion uniforms
        let dist_params = create_dist_params(
            config,
            width,
            height,
            self.sim_width,
            self.sim_height,
            self.time_elapsed,
        );
        self.queue.write_buffer(
            &self.resources.dist_uniform_buffer,
            0,
            bytemuck::cast_slice(&[dist_params]),
        );

        // Get current phase texture
        let phase_view = if self.current_phase {
            &self.resources.phase_view_b
        } else {
            &self.resources.phase_view_a
        };

        // Create bind group for distortion (input texture + phase texture)
        let dist_bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Dist Bind Group"),
            layout: &self.resources.dist_texture_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(input_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&self.resources.sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(phase_view),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::Sampler(&self.resources.non_filtering_sampler),
                },
            ],
        });

        // Render distortion pass
        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Oscillator Distortion Pass"),
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

            render_pass.set_pipeline(&self.pipelines.distortion_pipeline);
            render_pass.set_bind_group(0, &dist_bind_group, &[]);
            render_pass.set_bind_group(1, &self.resources.dist_uniform_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.resources.vertex_buffer.slice(..));
            render_pass
                .set_index_buffer(self.resources.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..6, 0, 0..1);
        }
    }
}

pub(crate) fn create_dist_params(
    config: &OscillatorConfig,
    width: u32,
    height: u32,
    sim_width: u32,
    sim_height: u32,
    time: f32,
) -> DistortionParams {
    DistortionParams {
        resolution: [width as f32, height as f32],
        sim_resolution: [sim_width as f32, sim_height as f32],
        distortion_amount: config.distortion_amount,
        distortion_scale: config.distortion_scale,
        distortion_speed: config.distortion_speed,
        overlay_opacity: config.overlay_opacity,
        time,
        color_mode: config.color_mode.to_u32(),
        use_log_polar: match config.coordinate_mode {
            vorce_core::CoordinateMode::LogPolar => 1,
            _ => 0,
        },
        _padding: 0.0,
    }
}
