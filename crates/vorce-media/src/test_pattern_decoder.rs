use std::time::Duration;
use vorce_io::VideoFrame;
use crate::{MediaError, Result, VideoDecoder};

/// A dummy decoder for testing purposes
#[derive(Clone)]
pub struct TestPatternDecoder {
    width: u32,
    height: u32,
    duration: Duration,
    fps: f64,
    current_time: Duration,
}

impl TestPatternDecoder {
    pub fn new(width: u32, height: u32, duration: Duration, fps: f64) -> Self {
        Self { width, height, duration, fps, current_time: Duration::ZERO }
    }
}

impl VideoDecoder for TestPatternDecoder {
    fn next_frame(&mut self) -> Result<VideoFrame> {
        let frame_duration = Duration::from_secs_f64(1.0 / self.fps);
        if self.current_time >= self.duration {
            return Err(MediaError::EndOfStream);
        }

        self.current_time += frame_duration;
        let data = vec![0; (self.width * self.height * 4) as usize];

        Ok(VideoFrame {
            data: data.into_boxed_slice(),
            width: self.width,
            height: self.height,
            stride: self.width * 4,
            format: crate::PixelFormat::Rgba8Unorm,
            timestamp: self.current_time,
            color_space: vorce_io::ColorSpace::Srgb,
            color_range: vorce_io::ColorRange::Full,
        })
    }

    fn seek(&mut self, timestamp: Duration) -> Result<()> {
        self.current_time = timestamp;
        Ok(())
    }

    fn duration(&self) -> Duration {
        self.duration
    }

    fn resolution(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    fn fps(&self) -> f64 {
        self.fps
    }

    fn clone_decoder(&self) -> Result<Box<dyn VideoDecoder>> {
        Ok(Box::new(self.clone()))
    }
}
