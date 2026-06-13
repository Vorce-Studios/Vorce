use crate::{
    reject_path_traversal, HwAccelType, MediaError, Result, VideoDecoder,
};
use std::path::Path;
use std::time::Duration;
use vorce_io::VideoFrame;

/// FFmpeg-based video decoder implementation.
pub struct FfmpegDecoder {
    #[cfg(feature = "ffmpeg")]
    context: ffmpeg_next::format::context::Input,
    #[cfg(feature = "ffmpeg")]
    video_stream_index: usize,
    #[cfg(feature = "ffmpeg")]
    decoder: ffmpeg_next::decoder::Video,
    #[cfg(feature = "ffmpeg")]
    scaler: ffmpeg_next::software::scaling::Context,
    #[cfg(feature = "ffmpeg")]
    duration: Duration,
    #[cfg(feature = "ffmpeg")]
    current_time: Duration,
    #[cfg(feature = "ffmpeg")]
    is_looping: bool,
    #[cfg(feature = "ffmpeg")]
    is_finished: bool,
    #[cfg(feature = "ffmpeg")]
    width: u32,
    #[cfg(feature = "ffmpeg")]
    height: u32,
    #[cfg(feature = "ffmpeg")]
    fps: f64,
}

// Safety: SwsContext is handled via ffmpeg-next which provides safe wrappers, 
// but we need to be careful with Send/Sync.
unsafe impl Send for FfmpegDecoder {}

impl FfmpegDecoder {
    /// Creates a new FFmpeg decoder for the given file path with hardware acceleration options.
    pub fn open_with_hw_accel(path: &Path, _hw_accel: HwAccelType) -> Result<Self> {
        Self::new(path)
    }

    /// Creates a new FFmpeg decoder for the given file path.
    pub fn new(path: &Path) -> Result<Self> {
        reject_path_traversal(path)?;

        #[cfg(feature = "ffmpeg")]
        {
            let context = ffmpeg_next::format::input(&path)
                .map_err(|e| MediaError::DecoderError(e.to_string()))?;
            let stream = context
                .streams()
                .best(ffmpeg_next::media::Type::Video)
                .ok_or_else(|| MediaError::DecoderError("No video stream found".to_string()))?;
            let video_stream_index = stream.index();

            let context_decoder =
                ffmpeg_next::codec::context::Context::from_parameters(stream.parameters())
                    .map_err(|e| MediaError::DecoderError(e.to_string()))?;
            let decoder = context_decoder
                .decoder()
                .video()
                .map_err(|e| MediaError::DecoderError(e.to_string()))?;

            let width = decoder.width();
            let height = decoder.height();
            let fps = stream.avg_frame_rate();
            let fps_val = fps.0 as f64 / fps.1 as f64;

            let scaler = ffmpeg_next::software::scaling::context::Context::get(
                decoder.format(),
                width,
                height,
                ffmpeg_next::format::Pixel::RGBA,
                width,
                height,
                ffmpeg_next::software::scaling::flag::Flags::BILINEAR,
            )
            .map_err(|e| MediaError::DecoderError(e.to_string()))?;

            let duration = Duration::from_micros(context.duration() as u64);

            Ok(Self {
                context,
                video_stream_index,
                decoder,
                scaler,
                duration,
                current_time: Duration::ZERO,
                is_looping: false,
                is_finished: false,
                width,
                height,
                fps: fps_val,
            })
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            let _ = path;
            Err(MediaError::FeatureNotEnabled("ffmpeg".to_string()))
        }
    }
}

impl VideoDecoder for FfmpegDecoder {
    fn next_frame(&mut self) -> Result<VideoFrame> {
        #[cfg(feature = "ffmpeg")]
        {
            Err(MediaError::DecoderError("Not implemented".to_string()))
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            Err(MediaError::FeatureNotEnabled("ffmpeg".to_string()))
        }
    }

    fn seek(&mut self, _timestamp: Duration) -> Result<()> {
        #[cfg(feature = "ffmpeg")]
        {
            Ok(())
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            Err(MediaError::FeatureNotEnabled("ffmpeg".to_string()))
        }
    }

    fn duration(&self) -> Duration {
        #[cfg(feature = "ffmpeg")]
        {
            self.duration
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            Duration::ZERO
        }
    }

    fn resolution(&self) -> (u32, u32) {
        #[cfg(feature = "ffmpeg")]
        {
            (self.width, self.height)
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            (0, 0)
        }
    }

    fn fps(&self) -> f64 {
        #[cfg(feature = "ffmpeg")]
        {
            self.fps
        }
        #[cfg(not(feature = "ffmpeg"))]
        {
            0.0
        }
    }

    fn clone_decoder(&self) -> Result<Box<dyn VideoDecoder>> {
        Err(MediaError::DecoderError("Cloning not supported for FFmpeg".to_string()))
    }
}
