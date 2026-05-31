//! Video decoder abstraction with FFmpeg implementation

use crate::Result;
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
// FFmpeg Implementation (when feature is enabled)
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_test_pattern_decoder() {
        let mut decoder = crate::test_pattern_decoder::TestPatternDecoder::new(
            640,
            480,
            Duration::from_secs(10),
            30.0,
        );

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
        let mut decoder = crate::test_pattern_decoder::TestPatternDecoder::new(
            640,
            480,
            Duration::from_secs(10),
            30.0,
        );

        decoder.seek(Duration::from_secs(5)).unwrap();
        assert_eq!(decoder.current_time, Duration::from_secs(5));

        // Seeking beyond duration should error
        assert!(decoder.seek(Duration::from_secs(15)).is_err());
    }

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
