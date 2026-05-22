use crate::{MediaError, Result, VideoDecoder};
use std::time::Duration;
use vorce_io::VideoFrame;

/// Test pattern decoder (fallback when FFmpeg is not available)
#[derive(Clone)]
pub struct TestPatternDecoder {
    width: u32,
    height: u32,
    duration: Duration,
    fps: f64,
    pub current_time: Duration,
    frame_count: u64,
}

impl TestPatternDecoder {
    /// Create a new test pattern decoder
    pub fn new(width: u32, height: u32, duration: Duration, fps: f64) -> Self {
        Self { width, height, duration, fps, current_time: Duration::ZERO, frame_count: 0 }
    }

    /// Generate a test pattern frame
    fn generate_test_frame(&self) -> VideoFrame {
        let size = (self.width * self.height * 4) as usize;
        let mut data = vec![0u8; size];

        // Generate animated gradient pattern
        let time_offset = (self.frame_count % 255) as u8;

        for y in 0..self.height {
            for x in 0..self.width {
                let idx = ((y * self.width + x) * 4) as usize;
                data[idx] = ((x * 255 / self.width) as u8).wrapping_add(time_offset);
                data[idx + 1] = ((y * 255 / self.height) as u8).wrapping_add(time_offset);
                data[idx + 2] = 128;
                data[idx + 3] = 255;
            }
        }

        VideoFrame::new(
            data,
            vorce_io::VideoFormat {
                width: self.width,
                height: self.height,
                pixel_format: vorce_io::PixelFormat::RGBA8,
                frame_rate: self.fps as f32,
            },
            self.current_time,
        )
    }
}

impl VideoDecoder for TestPatternDecoder {
    fn next_frame(&mut self) -> Result<VideoFrame> {
        if self.current_time >= self.duration {
            return Err(MediaError::EndOfStream);
        }

        let frame = self.generate_test_frame();

        self.current_time += Duration::from_secs_f64(1.0 / self.fps);
        self.frame_count += 1;

        Ok(frame)
    }

    fn seek(&mut self, timestamp: Duration) -> Result<()> {
        if timestamp > self.duration {
            return Err(MediaError::SeekError("Timestamp beyond duration".to_string()));
        }

        self.current_time = timestamp;
        self.frame_count = (timestamp.as_secs_f64() * self.fps) as u64;

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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_test_pattern_decoder() {
        let mut decoder = TestPatternDecoder::new(640, 480, Duration::from_secs(10), 30.0);

        assert_eq!(decoder.resolution(), (640, 480));
        assert_eq!(decoder.fps(), 30.0);
        assert_eq!(decoder.duration(), Duration::from_secs(10));

        let frame = decoder.next_frame().unwrap();
        assert_eq!(frame.format.width, 640);
        assert_eq!(frame.format.height, 480);
        assert_eq!(frame.format.pixel_format, vorce_io::PixelFormat::RGBA8);
    }

    #[test]
    fn test_test_pattern_seek() {
        let mut decoder = TestPatternDecoder::new(640, 480, Duration::from_secs(10), 30.0);

        decoder.seek(Duration::from_secs(5)).unwrap();
        assert_eq!(decoder.current_time, Duration::from_secs(5));

        // Seeking beyond duration should error
        assert!(decoder.seek(Duration::from_secs(15)).is_err());
    }
}
