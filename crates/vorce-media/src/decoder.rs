//! Video decoder abstraction with FFmpeg implementation

use crate::{MediaError, Result};
use std::time::Duration;

/// Pixel format for decoded frames
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PixelFormat {
    RGBA8,
    BGRA8,
    YUV420P,
}

use vorce_io::VideoFrame;

/// Convert YUV420P to RGBA using BT.601 color space
#[allow(dead_code)]
fn yuv420p_to_rgba(yuv_data: &[u8], width: u32, height: u32) -> Vec<u8> {
    let size = (width * height) as usize;
    let y_plane = &yuv_data[0..size];
    let u_plane = &yuv_data[size..size + size / 4];
    let v_plane = &yuv_data[size + size / 4..size + size / 2];

    let mut rgba = vec![0u8; size * 4];

    for y in 0..height {
        for x in 0..width {
            let y_idx = (y * width + x) as usize;
            let uv_idx = ((y / 2) * (width / 2) + (x / 2)) as usize;

            let y_val = y_plane[y_idx] as i32;
            let u_val = u_plane[uv_idx] as i32 - 128;
            let v_val = v_plane[uv_idx] as i32 - 128;

            // BT.601 conversion
            let r = (y_val + (1.402 * v_val as f32) as i32).clamp(0, 255) as u8;
            let g = (y_val - (0.344 * u_val as f32) as i32 - (0.714 * v_val as f32) as i32)
                .clamp(0, 255) as u8;
            let b = (y_val + (1.772 * u_val as f32) as i32).clamp(0, 255) as u8;

            let rgba_idx = y_idx * 4;
            rgba[rgba_idx] = r;
            rgba[rgba_idx + 1] = g;
            rgba[rgba_idx + 2] = b;
            rgba[rgba_idx + 3] = 255;
        }
    }

    rgba
}

/// Video decoder trait
///
/// Note: VideoDecoder requires Send to support multi-threaded decoding.
/// Implementations must ensure thread safety (e.g. by using Send wrappers for FFI types).
pub trait VideoDecoder: Send {
    fn next_frame(&mut self) -> Result<VideoFrame>;
    fn seek(&mut self, timestamp: Duration) -> Result<()>;
    fn duration(&self) -> Duration;
    fn resolution(&self) -> (u32, u32);
    fn fps(&self) -> f64;
    fn clone_decoder(&self) -> Result<Box<dyn VideoDecoder>>;
}

/// Hardware acceleration type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HwAccelType {
    None,
    #[cfg(target_os = "linux")]
    VAAPI,
    #[cfg(target_os = "macos")]
    VideoToolbox,
    #[cfg(target_os = "windows")]
    DXVA2,
    #[cfg(target_os = "windows")]
    D3D11VA,
}

// ============================================================================
// Test Pattern Fallback (always available)
// ============================================================================

/// Test pattern decoder (fallback when FFmpeg is not available)
#[derive(Clone)]
pub struct TestPatternDecoder {
    width: u32,
    height: u32,
    duration: Duration,
    fps: f64,
    current_time: Duration,
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

// ============================================================================
// Public API
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_yuv420p_conversion() {
        // Create a simple 2x2 YUV420P frame (white pixel)
        let mut yuv_data = vec![0u8; 6]; // 4 Y + 1 U + 1 V
        yuv_data[0..4].fill(255); // Y plane (white)
        yuv_data[4] = 128; // U
        yuv_data[5] = 128; // V

        let rgba = yuv420p_to_rgba(&yuv_data, 2, 2);

        // All pixels should be white (or close to white due to color space conversion)
        for chunk in rgba.chunks(4) {
            assert!(chunk[0] > 200); // R
            assert!(chunk[1] > 200); // G
            assert!(chunk[2] > 200); // B
            assert_eq!(chunk[3], 255); // A
        }
    }
}
