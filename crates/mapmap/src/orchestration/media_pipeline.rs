//! Media pipeline integration

use mapmap_media::pipeline::FramePipeline;
use mapmap_media::pipeline::FrameUploader;
use mapmap_media::player::{PlaybackCommand, PlaybackState, PlaybackStatus};
use mapmap_media::DecodedFrame;
use mapmap_render::TexturePool;
use std::sync::Arc;
use crossbeam_channel::{Sender, Receiver};

/// Wrapper for active media pipeline with control channels
pub struct ActiveMediaPipeline {
    /// The underlying frame pipeline
    pub pipeline: FramePipeline,
    /// Channel to send playback commands
    pub command_tx: Sender<PlaybackCommand>,
    /// Channel to receive playback status
    pub status_rx: Receiver<PlaybackStatus>,
    /// Name of the texture this pipeline uploads to
    pub texture_name: String,

    /// Cached duration for UI display
    pub duration: std::time::Duration,
    /// Current playback state
    pub current_state: PlaybackState,
    /// Path to the source media file
    pub source_path: String,
}

impl ActiveMediaPipeline {
    /// Create a new active media pipeline
    pub fn new(
        pipeline: FramePipeline,
        command_tx: Sender<PlaybackCommand>,
        status_rx: Receiver<PlaybackStatus>,
        texture_name: String,
        duration: std::time::Duration,
        source_path: String,
    ) -> Self {
        Self {
            pipeline,
            command_tx,
            status_rx,
            texture_name,
            duration,
            current_state: PlaybackState::Idle,
            source_path,
        }
    }

    /// Update the internal state by draining status channel
    pub fn update_state(&mut self) {
        while let Ok(status) = self.status_rx.try_recv() {
            match status {
                PlaybackStatus::StateChanged(state) => self.current_state = state,
                _ => {}
            }
        }
    }
}

/// WGPU implementation of FrameUploader
pub struct WgpuFrameUploader {
    /// WGPU Queue for texture upload
    pub queue: Arc<wgpu::Queue>,
    /// Texture pool for managing textures
    pub texture_pool: Arc<TexturePool>,
    /// Name of the target texture
    pub texture_name: String,
}

impl WgpuFrameUploader {
    /// Create a new WGPU frame uploader
    pub fn new(queue: Arc<wgpu::Queue>, texture_pool: Arc<TexturePool>, texture_name: String) -> Self {
        Self {
            queue,
            texture_pool,
            texture_name,
        }
    }
}

impl FrameUploader for WgpuFrameUploader {
    fn upload(&mut self, frame: &DecodedFrame) {
        let (width, height) = (frame.format.width, frame.format.height);

        // Ensure texture exists and has correct size/format
        // The pool handles resizing internally if dimensions change
        self.texture_pool.ensure_texture(
            &self.texture_name,
            width,
            height,
            wgpu::TextureFormat::Rgba8UnormSrgb,
            wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        );

        // Upload data if on CPU
        if let mapmap_io::format::FrameData::Cpu(data) = &frame.data {
             self.texture_pool.upload_data(
                &self.queue,
                &self.texture_name,
                data,
                width,
                height,
            );
        }
    }
}
