//! Video encoding using FFmpeg.
//!
//! This module provides video encoding capabilities for streaming using FFmpeg.

#[cfg(feature = "stream")]
use crate::error::{IoError, Result};
#[cfg(feature = "stream")]
use crate::format::{FrameData, PixelFormat, VideoFormat, VideoFrame};
#[cfg(feature = "stream")]
use ffmpeg_next as ffmpeg;

/// Video codec enumeration.
#[cfg(feature = "stream")]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoCodec {
    /// H.264 (AVC)
    H264,
    /// H.265 (HEVC)
    H265,
    /// VP8
    VP8,
    /// VP9
    VP9,
}

#[cfg(feature = "stream")]
impl VideoCodec {
    /// Returns the codec name for FFmpeg.
    pub fn ffmpeg_name(&self) -> &'static str {
        match self {
            VideoCodec::H264 => "libx264",
            VideoCodec::H265 => "libx265",
            VideoCodec::VP8 => "libvpx",
            VideoCodec::VP9 => "libvpx-vp9",
        }
    }
}

/// Encoder preset for quality/speed tradeoff.
#[cfg(feature = "stream")]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncoderPreset {
    /// Ultra fast encoding, lower quality
    UltraFast,
    /// Super fast encoding
    SuperFast,
    /// Very fast encoding
    VeryFast,
    /// Fast encoding
    Fast,
    /// Medium speed/quality (default)
    Medium,
    /// Slow encoding, better quality
    Slow,
    /// Very slow encoding, best quality
    VerySlow,
    /// Low latency preset for streaming
    LowLatency,
}

#[cfg(feature = "stream")]
impl EncoderPreset {
    /// Returns the preset name for FFmpeg.
    pub fn ffmpeg_name(&self) -> &'static str {
        match self {
            EncoderPreset::UltraFast => "ultrafast",
            EncoderPreset::SuperFast => "superfast",
            EncoderPreset::VeryFast => "veryfast",
            EncoderPreset::Fast => "fast",
            EncoderPreset::Medium => "medium",
            EncoderPreset::Slow => "slow",
            EncoderPreset::VerySlow => "veryslow",
            EncoderPreset::LowLatency => "ultrafast", // Use ultrafast for low latency
        }
    }
}

/// Video encoder using FFmpeg.
///
/// Encodes raw CPU video frames into compressed H.264/H.265/VP8/VP9 packets
/// suitable for RTMP or SRT streaming.
#[cfg(feature = "stream")]
pub struct VideoEncoder {
    codec: VideoCodec,
    format: VideoFormat,
    bitrate: u64,
    frame_count: u64,
    /// Opened FFmpeg video encoder context.
    encoder: ffmpeg::codec::encoder::video::Encoder,
    /// Pixel-format converter (input → YUV420P).
    scaler: ffmpeg::software::scaling::Context,
}

#[cfg(feature = "stream")]
impl VideoEncoder {
    /// Creates a new video encoder backed by FFmpeg.
    ///
    /// # Parameters
    ///
    /// - `codec`   – The video codec to use (H.264, H.265, VP8, VP9)
    /// - `format`  – The input video format (resolution, pixel format, fps)
    /// - `bitrate` – Target bitrate in bits per second
    /// - `preset`  – Encoder preset for quality/speed tradeoff
    pub fn new(
        codec: VideoCodec,
        format: VideoFormat,
        bitrate: u64,
        preset: EncoderPreset,
    ) -> Result<Self> {
        ffmpeg::init().map_err(|e| IoError::EncoderInitFailed(e.to_string()))?;

        let codec_name = codec.ffmpeg_name();
        let ffmpeg_codec = ffmpeg::encoder::find_by_name(codec_name).ok_or_else(|| {
            IoError::EncoderInitFailed(format!(
                "Encoder '{codec_name}' not found; ensure FFmpeg was compiled with the required libraries",
            ))
        })?;

        let ctx = ffmpeg::codec::context::Context::new_with_codec(ffmpeg_codec);
        let mut video = ctx
            .encoder()
            .video()
            .map_err(|e| IoError::EncoderInitFailed(format!("Failed to create encoder context: {e}")))?;

        video.set_width(format.width);
        video.set_height(format.height);
        // libx264/libx265 require YUV420P; the scaler converts from the input format.
        video.set_format(ffmpeg::format::Pixel::YUV420P);
        video.set_time_base((1, format.frame_rate.round() as i32));
        video.set_bit_rate(bitrate as usize);
        video.set_gop(60); // Force a keyframe every 60 frames
        video.set_max_b_frames(0); // Disable B-frames for minimum encoding latency

        let mut opts = ffmpeg::Dictionary::new();
        if matches!(codec, VideoCodec::H264 | VideoCodec::H265) {
            opts.set("preset", preset.ffmpeg_name());
            opts.set("tune", "zerolatency"); // Disable look-ahead buffering
        }

        let encoder = video
            .open_as_with(ffmpeg_codec, opts)
            .map_err(|e| IoError::EncoderInitFailed(format!("Failed to open encoder '{codec_name}': {e}")))?;

        // Build a pixel-format converter from the declared input format to YUV420P.
        let input_pix_fmt = Self::map_pixel_format(format.pixel_format)?;
        let scaler = ffmpeg::software::scaling::Context::get(
            input_pix_fmt,
            format.width,
            format.height,
            ffmpeg::format::Pixel::YUV420P,
            format.width,
            format.height,
            ffmpeg::software::scaling::Flags::BILINEAR,
        )
        .map_err(|e| IoError::EncoderInitFailed(format!("Failed to create pixel-format converter: {e}")))?;

        tracing::info!(
            codec = codec_name,
            width = format.width,
            height = format.height,
            fps = format.frame_rate,
            bitrate,
            "Video encoder initialised"
        );

        Ok(Self {
            codec,
            format,
            bitrate,
            frame_count: 0,
            encoder,
            scaler,
        })
    }

    /// Creates a default H.264 encoder for 1080p60 streaming.
    pub fn default_h264_1080p60() -> Result<Self> {
        Self::new(
            VideoCodec::H264,
            VideoFormat::hd_1080p60_rgba(),
            6_000_000, // 6 Mbps
            EncoderPreset::LowLatency,
        )
    }

    /// Creates a default H.264 encoder for 720p60 streaming.
    pub fn default_h264_720p60() -> Result<Self> {
        Self::new(
            VideoCodec::H264,
            VideoFormat::hd_720p60_rgba(),
            3_500_000, // 3.5 Mbps
            EncoderPreset::LowLatency,
        )
    }

    /// Encodes a single video frame and returns an encoded packet.
    ///
    /// When the encoder is still filling its internal pipeline the returned
    /// packet will have `data.is_empty() == true`; callers should skip
    /// transmission for such packets.
    pub fn encode(&mut self, frame: &VideoFrame) -> Result<EncodedPacket> {
        if let FrameData::Gpu(_) = &frame.data {
            return Err(IoError::UnsupportedPixelFormat(
                "Cannot encode a GPU-resident frame on the CPU.".to_string(),
            ));
        }

        if frame.format.pixel_format != self.format.pixel_format {
            return Err(IoError::ConversionError(format!(
                "Frame pixel format '{}' does not match encoder format '{}'",
                frame.format.pixel_format, self.format.pixel_format
            )));
        }

        let cpu_data: &[u8] = match &frame.data {
            FrameData::Cpu(arc) => arc,
            FrameData::Gpu(_) => unreachable!("GPU case handled above"),
        };

        // Build an FFmpeg source frame from the raw CPU bytes.
        let input_pix_fmt = Self::map_pixel_format(self.format.pixel_format)?;
        let mut src_frame = ffmpeg::util::frame::Video::new(
            input_pix_fmt,
            self.format.width,
            self.format.height,
        );

        // Copy pixel data into the frame while respecting FFmpeg's row stride.
        let bytes_per_pixel = self.format.pixel_format.bytes_per_pixel();
        let src_row_stride = self.format.width as usize * bytes_per_pixel;
        let dst_stride = src_frame.stride(0);
        let copy_width = src_row_stride.min(dst_stride);
        for y in 0..self.format.height as usize {
            let src_off = y * src_row_stride;
            let dst_off = y * dst_stride;
            if src_off + copy_width <= cpu_data.len() {
                src_frame.data_mut(0)[dst_off..dst_off + copy_width]
                    .copy_from_slice(&cpu_data[src_off..src_off + copy_width]);
            }
        }

        // Convert to YUV420P as required by libx264/libx265.
        let mut yuv_frame = ffmpeg::util::frame::Video::new(
            ffmpeg::format::Pixel::YUV420P,
            self.format.width,
            self.format.height,
        );
        self.scaler
            .run(&src_frame, &mut yuv_frame)
            .map_err(|e| IoError::EncodeFailed(format!("Pixel format conversion failed: {e}")))?;

        self.frame_count += 1;
        yuv_frame.set_pts(Some(self.frame_count as i64 - 1));

        self.encoder
            .send_frame(&yuv_frame)
            .map_err(|e| IoError::EncodeFailed(format!("send_frame failed: {e}")))?;

        let mut packet = ffmpeg::Packet::empty();
        match self.encoder.receive_packet(&mut packet) {
            Ok(()) => {
                tracing::trace!(
                    frame = self.frame_count,
                    pts = packet.pts().unwrap_or(-1),
                    is_key = packet.is_key(),
                    size = packet.size(),
                    "Frame encoded"
                );
                Ok(EncodedPacket {
                    data: packet.data().unwrap_or(&[]).to_vec(),
                    pts: packet.pts().unwrap_or(0),
                    dts: packet.dts().unwrap_or(0),
                    is_keyframe: packet.is_key(),
                })
            }
            // AVERROR(EAGAIN) = -11: encoder needs more frames before producing output.
            Err(ffmpeg::Error::Other { errno: -11 }) => Ok(EncodedPacket {
                data: Vec::new(),
                pts: self.frame_count as i64,
                dts: self.frame_count as i64,
                is_keyframe: false,
            }),
            Err(e) => Err(IoError::EncodeFailed(format!("receive_packet failed: {e}"))),
        }
    }

    /// Flushes all frames buffered inside the encoder.
    ///
    /// Must be called before closing the encoder to ensure every frame is encoded.
    pub fn flush(&mut self) -> Result<Vec<EncodedPacket>> {
        tracing::debug!(frames = self.frame_count, "Flushing encoder");

        self.encoder
            .send_eof()
            .map_err(|e| IoError::EncodeFailed(format!("send_eof failed: {e}")))?;

        let mut packets = Vec::new();
        let mut packet = ffmpeg::Packet::empty();
        loop {
            match self.encoder.receive_packet(&mut packet) {
                Ok(()) => packets.push(EncodedPacket {
                    data: packet.data().unwrap_or(&[]).to_vec(),
                    pts: packet.pts().unwrap_or(0),
                    dts: packet.dts().unwrap_or(0),
                    is_keyframe: packet.is_key(),
                }),
                Err(ffmpeg::Error::Eof) | Err(ffmpeg::Error::Other { errno: -11 }) => break,
                Err(e) => {
                    return Err(IoError::EncodeFailed(format!(
                        "flush receive_packet failed: {e}"
                    )))
                }
            }
        }

        Ok(packets)
    }

    /// Returns the number of frames encoded so far.
    pub fn frame_count(&self) -> u64 {
        self.frame_count
    }

    /// Returns the codec being used.
    pub fn codec(&self) -> VideoCodec {
        self.codec
    }

    /// Returns the encoder's input format.
    pub fn format(&self) -> &VideoFormat {
        &self.format
    }

    /// Returns the target bitrate in bits per second.
    pub fn bitrate(&self) -> u64 {
        self.bitrate
    }

    fn map_pixel_format(fmt: PixelFormat) -> Result<ffmpeg::format::Pixel> {
        match fmt {
            PixelFormat::RGBA8 => Ok(ffmpeg::format::Pixel::RGBA),
            PixelFormat::BGRA8 => Ok(ffmpeg::format::Pixel::BGRA),
            PixelFormat::RGB8 => Ok(ffmpeg::format::Pixel::RGB24),
            PixelFormat::YUV420P => Ok(ffmpeg::format::Pixel::YUV420P),
            PixelFormat::YUV422P => Ok(ffmpeg::format::Pixel::YUV422P),
            PixelFormat::UYVY => Ok(ffmpeg::format::Pixel::UYVY422),
            PixelFormat::NV12 => Ok(ffmpeg::format::Pixel::NV12),
        }
    }
}

/// An encoded video packet.
#[cfg(feature = "stream")]
#[derive(Debug, Clone)]
pub struct EncodedPacket {
    /// Compressed packet data
    pub data: Vec<u8>,
    /// Presentation timestamp
    pub pts: i64,
    /// Decode timestamp
    pub dts: i64,
    /// Whether this is a keyframe
    pub is_keyframe: bool,
}

#[cfg(feature = "stream")]
impl EncodedPacket {
    /// Returns the packet size in bytes.
    pub fn size(&self) -> usize {
        self.data.len()
    }
}

// Stub implementations when stream feature is disabled
/// Video encoder (stub implementation when feature is disabled)
#[cfg(not(feature = "stream"))]
pub struct VideoEncoder;

#[cfg(not(feature = "stream"))]
impl VideoEncoder {
    /// Create a new video encoder (returns error when feature is disabled)
    pub fn new() -> crate::error::Result<Self> {
        Err(crate::error::IoError::feature_not_enabled(
            "Stream encoding",
            "stream",
        ))
    }
}

#[cfg(test)]
#[cfg(feature = "stream")]
mod tests {
    use super::*;
    use crate::format::PixelFormat;

    /// Small format used for fast test encoding (avoids slow 1080p ops).
    fn small_format() -> VideoFormat {
        VideoFormat::new(320, 240, PixelFormat::RGBA8, 30.0)
    }

    #[test]
    fn test_video_codec_names() {
        assert_eq!(VideoCodec::H264.ffmpeg_name(), "libx264");
        assert_eq!(VideoCodec::H265.ffmpeg_name(), "libx265");
    }

    #[test]
    fn test_encoder_preset_names() {
        assert_eq!(EncoderPreset::UltraFast.ffmpeg_name(), "ultrafast");
        assert_eq!(EncoderPreset::Medium.ffmpeg_name(), "medium");
        assert_eq!(EncoderPreset::LowLatency.ffmpeg_name(), "ultrafast");
    }

    #[test]
    fn test_video_encoder_creation() {
        let encoder =
            VideoEncoder::new(VideoCodec::H264, small_format(), 500_000, EncoderPreset::UltraFast);
        assert!(encoder.is_ok(), "Encoder creation failed: {:?}", encoder.err());

        let encoder = encoder.unwrap();
        assert_eq!(encoder.codec(), VideoCodec::H264);
        assert_eq!(encoder.frame_count(), 0);
    }

    #[test]
    fn test_video_encoder_encode() {
        let fmt = small_format();
        let mut encoder =
            VideoEncoder::new(VideoCodec::H264, fmt.clone(), 500_000, EncoderPreset::UltraFast)
                .unwrap();

        let frame = VideoFrame::empty(fmt);
        let packet = encoder.encode(&frame);
        assert!(packet.is_ok(), "Encode failed: {:?}", packet.err());
        assert_eq!(encoder.frame_count(), 1);
    }

    #[test]
    fn test_video_encoder_keyframe() {
        let fmt = small_format();
        let mut encoder =
            VideoEncoder::new(VideoCodec::H264, fmt.clone(), 500_000, EncoderPreset::UltraFast)
                .unwrap();

        // With tune=zerolatency there is no look-ahead; the first frame must
        // produce an immediate IDR (keyframe) packet.
        let pkt = encoder.encode(&VideoFrame::empty(fmt.clone())).unwrap();
        assert!(!pkt.data.is_empty(), "Expected non-empty first packet");
        assert!(pkt.is_keyframe, "First encoded frame must be a keyframe (IDR)");

        // Encode until the second GOP boundary (gop=60 → IDR at frame 61, PTS=60).
        for _ in 0..59 {
            encoder.encode(&VideoFrame::empty(fmt.clone())).unwrap();
        }
        let pkt_61 = encoder.encode(&VideoFrame::empty(fmt.clone())).unwrap();
        assert!(!pkt_61.data.is_empty(), "Expected non-empty packet at GOP boundary");
        assert!(pkt_61.is_keyframe, "Frame 61 must start a new GOP (keyframe)");
    }

    #[test]
    fn test_video_encoder_wrong_format() {
        let mut encoder =
            VideoEncoder::new(VideoCodec::H264, small_format(), 500_000, EncoderPreset::UltraFast)
                .unwrap();

        let wrong_format = VideoFormat::new(320, 240, PixelFormat::YUV420P, 30.0);
        let frame = VideoFrame::empty(wrong_format);
        let result = encoder.encode(&frame);
        assert!(result.is_err(), "Expected error for mismatched pixel format");
    }
}
