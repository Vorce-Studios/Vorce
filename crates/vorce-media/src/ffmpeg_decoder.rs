use crate::{
    reject_path_traversal, test_pattern_decoder::TestPatternDecoder, HwAccelType,
    MediaError, Result, VideoDecoder,
};
use std::path::Path;
use std::time::Duration;
use tracing::info;
#[cfg(feature = "ffmpeg")]
use tracing::warn;
use vorce_io::VideoFrame;

#[cfg(feature = "ffmpeg")]
mod ffmpeg_impl {
    use super::*;
    use ffmpeg_next as ffmpeg;
    use ffmpeg_sys_next as ffi;
    use std::path::PathBuf;

    #[cfg(target_os = "windows")]
    unsafe extern "C" fn get_format_callback(
        ctx: *mut ffi::AVCodecContext,
        fmt: *const ffi::AVPixelFormat,
    ) -> ffi::AVPixelFormat {
        const MAX_FORMATS: usize = 128;

        if fmt.is_null() {
            warn!("get_format_callback: fmt is null");
            return ffi::AVPixelFormat::AV_PIX_FMT_NONE;
        }

        let mut p = fmt;
        let mut count = 0;
        while *p != ffi::AVPixelFormat::AV_PIX_FMT_NONE {
            if count >= MAX_FORMATS {
                warn!("get_format_callback: format list exceeded limit of {}", MAX_FORMATS);
                break;
            }
            if *p == ffi::AVPixelFormat::AV_PIX_FMT_D3D11 {
                return *p;
            }
            p = p.offset(1);
            count += 1;
        }

        ffi::avcodec_default_get_format(ctx, fmt)
    }

    pub struct RealFFmpegDecoder {
        input_ctx: ffmpeg::format::context::Input,
        decoder: ffmpeg::codec::decoder::Video,
        video_stream_idx: usize,
        time_base: ffmpeg::Rational,
        duration: Duration,
        fps: f64,
        width: u32,
        height: u32,
        current_format: ffmpeg::format::Pixel,
        hw_accel: HwAccelType,
        path: PathBuf,
    }

    impl RealFFmpegDecoder {
        pub fn try_clone(&self) -> Result<Self> {
            Self::open(self.path.clone(), self.hw_accel)
        }
    }

    impl RealFFmpegDecoder {
        /// Open a video file with optional hardware acceleration
        pub fn open<P: AsRef<Path>>(path: P, hw_accel: HwAccelType) -> Result<Self> {
            let path = path.as_ref();
            reject_path_traversal(path)?;

            if !path.exists() {
                return Err(MediaError::FileOpen(format!("File not found: {}", path.display())));
            }

            // Initialize FFmpeg
            ffmpeg::init().map_err(|e| MediaError::DecoderError(e.to_string()))?;

            // Open input file
            let input_ctx =
                ffmpeg::format::input(&path).map_err(|e| MediaError::FileOpen(e.to_string()))?;

            // Find best video stream
            let video_stream = input_ctx
                .streams()
                .best(ffmpeg::media::Type::Video)
                .ok_or(MediaError::NoVideoStream)?;

            let video_stream_idx = video_stream.index();
            let time_base = video_stream.time_base();

            // Get stream parameters
            let codec_params = video_stream.parameters();

            // Calculate FPS
            let fps = video_stream.avg_frame_rate();
            let fps_value = if fps.denominator() == 0 {
                30.0 // Default fallback
            } else {
                fps.numerator() as f64 / fps.denominator() as f64
            };

            // Calculate duration
            let raw_duration = video_stream.duration();
            let duration_secs = if raw_duration == i64::MIN {
                // AV_NOPTS_VALUE
                f64::NAN
            } else {
                raw_duration as f64 * f64::from(time_base)
            };

            if duration_secs.is_nan() {
                info!(
                    "Video info: FPS={:.2}, RawDuration=AV_NOPTS_VALUE, TimeBase={}/{}, CalcDuration=UNKNOWN",
                    fps_value,
                    time_base.numerator(),
                    time_base.denominator()
                );
            } else {
                info!(
                    "Video info: FPS={:.2}, RawDuration={}, TimeBase={}/{}, CalcDuration={:.2}s",
                    fps_value,
                    raw_duration,
                    time_base.numerator(),
                    time_base.denominator(),
                    duration_secs
                );
            }

            let duration = if duration_secs < 0.0 || duration_secs.is_nan() {
                if !duration_secs.is_nan() {
                    warn!(
                        "Negative video duration detected: {} seconds. Treating as unknown.",
                        duration_secs
                    );
                }
                Duration::ZERO
            } else {
                Duration::from_secs_f64(duration_secs)
            };

            // Create decoder context
            let mut decoder = ffmpeg::codec::Context::from_parameters(codec_params)
                .map_err(|e| MediaError::DecoderError(e.to_string()))?
                .decoder()
                .video()
                .map_err(|e| MediaError::DecoderError(e.to_string()))?;

            // Setup hardware acceleration if requested
            let actual_hw_accel = match Self::setup_hw_accel(&mut decoder, hw_accel) {
                Ok(accel) => accel,
                Err(e) => {
                    warn!(
                        "Failed to setup hardware acceleration {:?}: {}. Falling back to software decoding.",
                        hw_accel, e
                    );
                    HwAccelType::None
                }
            };

            // Get dimensions from decoder
            let width = decoder.width();
            let height = decoder.height();

            info!(
                "Decoder initialized successfully: {}x{} @ {:.2} fps, duration: {:.2}s, hw_accel: {:?}",
                width,
                height,
                fps_value,
                duration.as_secs_f64(),
                actual_hw_accel
            );

            let current_format = decoder.format();

            Ok(Self {
                input_ctx,
                decoder,

                video_stream_idx,
                time_base,
                duration,
                fps: fps_value,
                width,
                height,
                current_format,
                hw_accel: actual_hw_accel,
                path: path.to_path_buf(),
            })
        }

        /// Setup hardware acceleration
        fn setup_hw_accel(
            _decoder: &mut ffmpeg::codec::decoder::Video,
            requested: HwAccelType,
        ) -> Result<HwAccelType> {
            match requested {
                HwAccelType::None => Ok(HwAccelType::None),
                #[cfg(target_os = "windows")]
                HwAccelType::D3D11VA => unsafe {
                    let mut hw_device_ctx: *mut ffi::AVBufferRef = std::ptr::null_mut();
                    let ret = ffi::av_hwdevice_ctx_create(
                        &mut hw_device_ctx,
                        ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_D3D11VA,
                        std::ptr::null(),
                        std::ptr::null_mut(),
                        0,
                    );

                    if ret < 0 {
                        // Return error so we can log it properly in caller
                        return Err(MediaError::DecoderError(format!(
                            "Failed to create D3D11VA device context: {}",
                            ret
                        )));
                    }

                    let codec_ctx = _decoder.as_mut_ptr();
                    if codec_ctx.is_null() {
                        ffi::av_buffer_unref(&mut hw_device_ctx);
                        return Err(MediaError::DecoderError("Codec context is null".to_string()));
                    }

                    // Transfer ownership of hw_device_ctx to codec_ctx
                    (*codec_ctx).hw_device_ctx = hw_device_ctx;
                    (*codec_ctx).get_format = Some(get_format_callback);

                    info!("D3D11VA hardware acceleration initialized");
                    Ok(HwAccelType::D3D11VA)
                },
                _ => {
                    // Just fallback for unsupported types
                    Ok(HwAccelType::None)
                }
            }
        }
    }

    impl super::VideoDecoder for RealFFmpegDecoder {
        fn next_frame(&mut self) -> Result<VideoFrame> {
            let mut packets_processed = 0;
            const MAX_PACKETS_PER_CALL: usize = 50;

            for (stream, packet) in self.input_ctx.packets() {
                packets_processed += 1;
                if packets_processed >= MAX_PACKETS_PER_CALL {
                    return Err(MediaError::WouldBlock);
                }

                if stream.index() != self.video_stream_idx {
                    continue;
                }

                self.decoder
                    .send_packet(&packet)
                    .map_err(|e| MediaError::DecoderError(e.to_string()))?;

                let mut decoded = ffmpeg::util::frame::Video::empty();

                if self.decoder.receive_frame(&mut decoded).is_ok() {
                    #[allow(unused_variables, unused_mut)]
                    let mut sw_frame = ffmpeg::util::frame::Video::empty();
                    let frame_ptr = if unsafe {
                        (*decoded.as_ptr()).format == ffi::AVPixelFormat::AV_PIX_FMT_D3D11 as i32
                    } {
                        #[cfg(target_os = "windows")]
                        unsafe {
                            let ret = ffi::av_hwframe_transfer_data(
                                sw_frame.as_mut_ptr(),
                                decoded.as_ptr(),
                                0,
                            );
                            if ret < 0 {
                                return Err(MediaError::DecoderError(format!(
                                    "Failed to transfer HW frame: {}",
                                    ret
                                )));
                            }
                            ffi::av_frame_copy_props(sw_frame.as_mut_ptr(), decoded.as_ptr());
                            &sw_frame
                        }
                        #[cfg(not(target_os = "windows"))]
                        {
                            warn!("D3D11 frame format detected on non-Windows platform");
                            &decoded
                        }
                    } else {
                        &decoded
                    };

                    let frame_width = frame_ptr.width();
                    let frame_height = frame_ptr.height();
                    let frame_format = frame_ptr.format();
                    if frame_width != self.width
                        || frame_height != self.height
                        || frame_format != self.current_format
                    {
                        info!(
                            "Input changed: {}x{} {:?} -> {}x{} {:?}",
                            self.width,
                            self.height,
                            self.current_format,
                            frame_width,
                            frame_height,
                            frame_format
                        );

                        self.width = frame_width;
                        self.height = frame_height;
                        self.current_format = frame_format;
                    }

                    // Scale to RGBA
                    let mut rgb_frame = ffmpeg::util::frame::Video::empty();

                    thread_local! {
                        static SCALER: std::cell::RefCell<Option<(
                            ffmpeg::format::Pixel,
                            u32,
                            u32,
                            ffmpeg::software::scaling::Context
                        )>> = const { std::cell::RefCell::new(None) };
                    }

                    SCALER.with(|scaler_cell| -> Result<()> {
                        let mut scaler_opt = scaler_cell.borrow_mut();

                        let needs_new_scaler = match &*scaler_opt {
                            Some((fmt, w, h, _)) => {
                                *fmt != frame_format || *w != frame_width || *h != frame_height
                            }
                            None => true,
                        };

                        if needs_new_scaler {
                            let new_scaler = ffmpeg::software::scaling::Context::get(
                                frame_format,
                                frame_width,
                                frame_height,
                                ffmpeg::format::Pixel::RGBA,
                                frame_width,
                                frame_height,
                                ffmpeg::software::scaling::Flags::BILINEAR,
                            )
                            .map_err(|e| {
                                MediaError::DecoderError(format!(
                                    "Failed to recreate scaler: {}",
                                    e
                                ))
                            })?;

                            *scaler_opt =
                                Some((frame_format, frame_width, frame_height, new_scaler));
                        }

                        if let Some((_, _, _, scaler)) = scaler_opt.as_mut() {
                            scaler.run(frame_ptr, &mut rgb_frame).map_err(|e| {
                                MediaError::DecoderError(format!(
                                    "Decoder error: Input changed? Scaler run failed: {}",
                                    e
                                ))
                            })?;
                        }

                        Ok(())
                    })?;

                    let pts = Duration::from_secs_f64(
                        decoded.timestamp().unwrap_or(0) as f64 * f64::from(self.time_base),
                    );

                    // Copy to a tight buffer to remove FFmpeg's alignment padding.
                    // This ensures compatibility with wgpu and other parts of the system
                    // that expect exactly width * height * 4 bytes.
                    let width_bytes = self.width as usize * 4;
                    let mut tight_data = Vec::with_capacity(width_bytes * self.height as usize);
                    let stride = rgb_frame.stride(0);
                    let src_data = rgb_frame.data(0);

                    for y in 0..self.height as usize {
                        let start = y * stride;
                        let end = start + width_bytes;
                        if end <= src_data.len() {
                            tight_data.extend_from_slice(&src_data[start..end]);
                        }
                    }

                    return Ok(VideoFrame::new(
                        tight_data,
                        vorce_io::VideoFormat {
                            width: self.width,
                            height: self.height,
                            pixel_format: vorce_io::PixelFormat::RGBA8,
                            frame_rate: self.fps as f32,
                        },
                        pts,
                    ));
                }
            }

            Err(MediaError::EndOfStream)
        }

        fn seek(&mut self, timestamp: Duration) -> Result<()> {
            let timestamp_ts = (timestamp.as_secs_f64() / f64::from(self.time_base)) as i64;

            self.input_ctx
                .seek(timestamp_ts, ..)
                .map_err(|e| MediaError::SeekError(e.to_string()))?;

            // Flush decoder buffers
            self.decoder.flush();

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
            Ok(Box::new(self.try_clone()?))
        }
    }
}

/// Unified decoder that automatically uses FFmpeg if available, test pattern otherwise
pub enum FFmpegDecoder {
    #[cfg(feature = "ffmpeg")]
    Real(ffmpeg_impl::RealFFmpegDecoder),
    TestPattern(TestPatternDecoder),
}

impl FFmpegDecoder {
    /// Open a video file (uses FFmpeg if feature is enabled, test pattern otherwise)
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        Self::open_with_auto_hw_accel(path)
    }

    /// Open a video file with hardware acceleration
    pub fn open_with_hw_accel<P: AsRef<Path>>(_path: P, _hw_accel: HwAccelType) -> Result<Self> {
        #[cfg(feature = "ffmpeg")]
        {
            match ffmpeg_impl::RealFFmpegDecoder::open(&_path, _hw_accel) {
                Ok(decoder) => Ok(FFmpegDecoder::Real(decoder)),
                Err(e) => {
                    // IF IT'S A REAL FILE REQUEST, DON'T FALLBACK SILENTLY
                    if _path.as_ref().exists() {
                        return Err(e);
                    }
                    warn!("FFmpeg decoder failed: {}, using test pattern", e);
                    Ok(FFmpegDecoder::TestPattern(TestPatternDecoder::new(
                        1920,
                        1080,
                        Duration::from_secs(60),
                        30.0,
                    )))
                }
            }
        }

        #[cfg(not(feature = "ffmpeg"))]
        {
            // IF IT'S A REAL FILE REQUEST AND NO FFMPEG, ERROR OUT
            if _path.as_ref().exists() {
                return Err(MediaError::DecoderError(
                    "FFmpeg feature not enabled, cannot open video file".to_string(),
                ));
            }
            info!("FFmpeg feature not enabled, using test pattern");
            Ok(FFmpegDecoder::TestPattern(TestPatternDecoder::new(
                1920,
                1080,
                Duration::from_secs(60),
                30.0,
            )))
        }
    }

    /// Detect and use best available hardware acceleration
    pub fn open_with_auto_hw_accel<P: AsRef<Path>>(path: P) -> Result<Self> {
        #[cfg(target_os = "linux")]
        let hw_accel = HwAccelType::VAAPI;

        #[cfg(target_os = "macos")]
        let hw_accel = HwAccelType::VideoToolbox;

        #[cfg(target_os = "windows")]
        let hw_accel = HwAccelType::D3D11VA;

        #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
        let hw_accel = HwAccelType::None;

        Self::open_with_hw_accel(path, hw_accel)
    }
}

impl VideoDecoder for FFmpegDecoder {
    fn next_frame(&mut self) -> Result<VideoFrame> {
        match self {
            #[cfg(feature = "ffmpeg")]
            FFmpegDecoder::Real(decoder) => decoder.next_frame(),
            FFmpegDecoder::TestPattern(decoder) => decoder.next_frame(),
        }
    }

    fn seek(&mut self, timestamp: Duration) -> Result<()> {
        match self {
            #[cfg(feature = "ffmpeg")]
            FFmpegDecoder::Real(decoder) => decoder.seek(timestamp),
            FFmpegDecoder::TestPattern(decoder) => decoder.seek(timestamp),
        }
    }

    fn duration(&self) -> Duration {
        match self {
            #[cfg(feature = "ffmpeg")]
            FFmpegDecoder::Real(decoder) => decoder.duration(),
            FFmpegDecoder::TestPattern(decoder) => decoder.duration(),
        }
    }

    fn resolution(&self) -> (u32, u32) {
        match self {
            #[cfg(feature = "ffmpeg")]
            FFmpegDecoder::Real(decoder) => decoder.resolution(),
            FFmpegDecoder::TestPattern(decoder) => decoder.resolution(),
        }
    }

    fn fps(&self) -> f64 {
        match self {
            #[cfg(feature = "ffmpeg")]
            FFmpegDecoder::Real(decoder) => decoder.fps(),
            FFmpegDecoder::TestPattern(decoder) => decoder.fps(),
        }
    }

    fn clone_decoder(&self) -> Result<Box<dyn VideoDecoder>> {
        match self {
            #[cfg(feature = "ffmpeg")]
            FFmpegDecoder::Real(decoder) => decoder.clone_decoder(),
            FFmpegDecoder::TestPattern(decoder) => decoder.clone_decoder(),
        }
    }
}
