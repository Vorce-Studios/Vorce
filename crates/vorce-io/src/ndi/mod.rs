//! NDI (Network Device Interface) support.
//!
//! **[Experimental] / [Gated]**
//! This feature is currently experimental and not fully integrated into the production render path.
//!
//! This module provides NDI input (receiving) and output (sending) capabilities
//! using the grafton-ndi crate which wraps the official NDI SDK.

#[cfg(feature = "ndi")]
use crate::error::{IoError, Result};
#[cfg(feature = "ndi")]
use crate::format::{FrameData, PixelFormat, VideoFormat, VideoFrame};

#[cfg(feature = "ndi")]
use grafton_ndi::{Finder, Receiver, ReceiverColorFormat, NDI};
#[cfg(feature = "ndi")]
use std::sync::Arc;
#[cfg(feature = "ndi")]
use std::time::Duration;
#[cfg(feature = "ndi")]
use tracing::{error, info, warn};

/// Re-export Source type for external use
#[cfg(feature = "ndi")]
pub use grafton_ndi::Source;

/// Wrapper for NDI Source that is Send + Sync safe
#[cfg(feature = "ndi")]
#[derive(Debug, Clone)]
pub struct NdiSource {
    /// The name of the NDI source
    pub name: String,
    /// The URL/address of the source (if available)
    pub url_address: Option<String>,
}

#[cfg(feature = "ndi")]
impl From<grafton_ndi::Source> for NdiSource {
    fn from(source: grafton_ndi::Source) -> Self {
        let url_address = match &source.address {
            grafton_ndi::SourceAddress::Url(url) => Some(url.clone()),
            grafton_ndi::SourceAddress::Ip(ip) => Some(ip.clone()),
            grafton_ndi::SourceAddress::None => None,
        };
        
        Self {
            name: source.name.clone(),
            url_address,
        }
    }
}

/// NDI receiver for capturing video from NDI sources.
#[cfg(feature = "ndi")]
pub struct NdiReceiver {
    /// NDI library handle
    _ndi: Option<NDI>,
    /// Current source info
    source_info: Option<NdiSource>,
    /// Video format
    _format: VideoFormat,
    /// Frame counter
    frame_count: u64,
    /// NDI receiver instance
    recv: Option<Receiver>,
}

#[cfg(feature = "ndi")]
impl NdiReceiver {
    /// Creates a new NDI receiver.
    pub fn new() -> Result<Self> {
        info!("Creating NDI Receiver");

        Ok(Self {
            _ndi: None,
            source_info: None,
            _format: VideoFormat::hd_1080p30_rgba(),
            frame_count: 0,
            recv: None,
        })
    }

    /// Discovers available NDI sources on the network.
    ///
    /// This is a blocking call that waits for the specified timeout.
    pub fn discover_sources(timeout_ms: u32) -> Result<Vec<NdiSource>> {
        info!("Starting NDI source discovery for {}ms", timeout_ms);

        // Initialize NDI temporarily for discovery
        let ndi = NDI::new().map_err(|e| {
            error!("Failed to initialize NDI for discovery: {}", e);
            IoError::NdiError(format!("Failed to initialize NDI: {}", e))
        })?;

        let finder_options = grafton_ndi::FinderOptions::default();
        let finder = Finder::new(&ndi, &finder_options).map_err(|e| {
            error!("Failed to create NDI finder: {}", e);
            IoError::NdiError(format!("Failed to create NDI finder: {}", e))
        })?;

        // Wait for sources
        let timeout = Duration::from_millis(timeout_ms as u64);
        let sources = finder.find_sources(timeout).map_err(|e| {
            error!("Failed to find NDI sources: {}", e);
            IoError::NdiError(format!("Failed to find sources: {}", e))
        })?;
        
        let ndi_sources: Vec<NdiSource> = sources.into_iter().map(|s| s.into()).collect();

        info!("Found {} NDI sources", ndi_sources.len());
        for source in &ndi_sources {
            info!("  - {}", source.name);
        }

        Ok(ndi_sources)
    }

    /// Discovers sources asynchronously via a channel
    pub fn discover_sources_async(sender: std::sync::mpsc::Sender<Vec<NdiSource>>) {
        std::thread::spawn(move || match Self::discover_sources(3000) {
            Ok(sources) => {
                let _ = sender.send(sources);
            }
            Err(e) => {
                error!("NDI discovery failed: {}", e);
                let _ = sender.send(vec![]);
            }
        });
    }

    /// Connects to a specific NDI source by name.
    pub fn connect(&mut self, source: &NdiSource) -> Result<()> {
        info!("Connecting to NDI source: {}", source.name);

        // We need a Source object for the receiver
        // First, discover to find the matching source
        let ndi = NDI::new()
            .map_err(|e| IoError::NdiError(format!("Failed to initialize NDI: {}", e)))?;

        let finder_options = grafton_ndi::FinderOptions::default();
        let finder = Finder::new(&ndi, &finder_options)
            .map_err(|e| IoError::NdiError(format!("Failed to create finder: {}", e)))?;

        // Wait briefly for sources
        let timeout = Duration::from_secs(2);
        let sources = finder.find_sources(timeout).map_err(|e| {
            IoError::NdiError(format!("Failed to find sources: {}", e))
        })?;

        let matching_source = sources
            .into_iter()
            .find(|s| s.name == source.name)
            .ok_or_else(|| {
                IoError::NdiError(format!("Source '{}' not found on network", source.name))
            })?;

        // Create receiver options
        let receiver_options = grafton_ndi::ReceiverOptions::builder(matching_source.clone())
            .color(ReceiverColorFormat::UYVY_BGRA)
            .build();

        // Create receiver
        let recv = Receiver::new(&ndi, &receiver_options).map_err(|e| {
            error!("Failed to create NDI receiver: {}", e);
            IoError::NdiError(format!("Failed to create receiver: {}", e))
        })?;

        self.recv = Some(recv);
        self.source_info = Some(source.clone());
        self._ndi = Some(ndi);

        info!("Successfully connected to NDI source: {}", source.name);
        Ok(())
    }

    /// Receives a frame with a timeout.
    /// Returns Ok(Some(frame)) if a frame was received,
    /// Ok(None) if no frame was available within the timeout.
    pub fn receive(&mut self, timeout: Duration) -> Result<Option<VideoFrame>> {
        let recv = self
            .recv
            .as_ref()
            .ok_or_else(|| IoError::NdiError("Not connected to any source".to_string()))?;

        match recv.capture_video(timeout) {
            Ok(video_frame) => {
                // Extract frame data from fields
                let width = video_frame.width as u32;
                let height = video_frame.height as u32;
                let frame_rate =
                    video_frame.frame_rate_n as f32 / video_frame.frame_rate_d.max(1) as f32;

                // Data is already a Vec<u8> in the new API
                let data = if !video_frame.data.is_empty() {
                    video_frame.data.clone()
                } else {
                    warn!("NDI frame has empty data");
                    return Ok(None);
                };

                let format = VideoFormat {
                    width,
                    height,
                    pixel_format: PixelFormat::BGRA8,
                    frame_rate,
                };

                self._format = format.clone();
                self.frame_count += 1;

                let frame = VideoFrame {
                    data: FrameData::Cpu(Arc::new(data)),
                    format,
                    timestamp: Duration::from_nanos(video_frame.timestamp.max(0) as u64),
                    metadata: Default::default(),
                };

                Ok(Some(frame))
            }
            Err(e) => {
                warn!("NDI capture error: {:?}", e);
                Ok(None)
            }
        }
    }

    /// Returns the name of the connected source, if any.
    pub fn source_name(&self) -> Option<&str> {
        self.source_info.as_ref().map(|s| s.name.as_str())
    }

    /// Returns whether a source is connected.
    pub fn is_connected(&self) -> bool {
        self.recv.is_some()
    }
}

#[cfg(feature = "ndi")]
impl Default for NdiReceiver {
    fn default() -> Self {
        Self::new().expect("Failed to create default NdiReceiver")
    }
}

// Note: NdiReceiver cannot implement VideoSource trait because Recv is not Send.
// The receiver must be used on the same thread where it was created.
// For cross-thread usage, wrap in a dedicated thread with channels.

/// NDI sender for broadcasting video to the network.
///
/// **[Experimental] / [Gated]**
/// Note: Sender implementation is a placeholder - grafton-ndi Send API needs verification.
#[cfg(feature = "ndi")]
pub struct NdiSender {
    /// NDI library handle
    _ndi: NDI,
    /// Sender name
    name: String,
    /// Video format
    _format: VideoFormat,
    /// Frame counter
    frame_count: u64,
    /// NDI send instance
    send: Option<grafton_ndi::Sender>,
}

#[cfg(feature = "ndi")]
impl NdiSender {
    /// Creates a new NDI sender with the given name.
    pub fn new(name: impl Into<String>, format: VideoFormat) -> Result<Self> {
        let name = name.into();
        info!("Creating NDI Sender: {}", name);

        let ndi = NDI::new().map_err(|e| {
            error!("Failed to initialize NDI library: {}", e);
            IoError::NdiSenderFailed(format!("Failed to initialize NDI: {}", e))
        })?;

        // Create sender options
        let sender_options = grafton_ndi::SenderOptions::builder(name.clone())
            .clock_video(true)
            .clock_audio(false)
            .build();

        let send = grafton_ndi::Sender::new(&ndi, &sender_options).map_err(|e| {
            error!("Failed to create NDI sender: {}", e);
            IoError::NdiSenderFailed(format!("Failed to create sender: {}", e))
        })?;

        info!("NDI Sender '{}' created successfully", name);

        Ok(Self {
            _ndi: ndi,
            name,
            _format: format,
            frame_count: 0,
            send: Some(send),
        })
    }

    /// Sends a video frame.
    pub fn send_frame(&mut self, frame: &VideoFrame) -> Result<()> {
        let send = self
            .send
            .as_ref()
            .ok_or_else(|| IoError::NdiSenderFailed("Sender not initialized".to_string()))?;

        // Extract CPU data
        let data = match &frame.data {
            FrameData::Cpu(data) => data,
            FrameData::Gpu(_) => {
                return Err(IoError::NdiSenderFailed(
                    "GPU frames must be downloaded to CPU before sending".to_string(),
                ));
            }
        };

        // Create NDI video frame and send
        // Construct a VideoFrame (grafton-ndi 0.11.0+)
        let line_stride = (frame.format.width * 4) as i32;
        let video_frame = grafton_ndi::VideoFrame {
            width: frame.format.width as i32,
            height: frame.format.height as i32,
            pixel_format: grafton_ndi::PixelFormat::BGRA,
            frame_rate_n: (frame.format.frame_rate * 1000.0) as i32,
            frame_rate_d: 1000,
            picture_aspect_ratio: frame.format.width as f32 / frame.format.height as f32,
            scan_type: grafton_ndi::ScanType::Progressive,
            timecode: 0,
            data: data.to_vec(),
            line_stride_or_size: grafton_ndi::LineStrideOrSize::LineStrideBytes(line_stride),
            metadata: None,
            timestamp: frame.timestamp.as_nanos() as i64,
        };

        send.send_video(&video_frame);

        self.frame_count += 1;

        Ok(())
    }

    /// Returns the sender name.
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Returns the number of frames sent.
    pub fn frame_count(&self) -> u64 {
        self.frame_count
    }
}

// Stub implementations when NDI feature is disabled
/// NDI receiver stub (NDI feature disabled)
#[cfg(not(feature = "ndi"))]
pub struct NdiReceiver;

#[cfg(not(feature = "ndi"))]
impl NdiReceiver {
    /// Create a new NDI receiver stub
    pub fn new() -> std::result::Result<Self, String> {
        Err("NDI feature not enabled".to_string())
    }
}

/// NDI sender stub (NDI feature disabled)
#[cfg(not(feature = "ndi"))]
pub struct NdiSender;

#[cfg(not(feature = "ndi"))]
impl NdiSender {
    /// Create a new NDI sender stub
    pub fn new(
        _name: impl Into<String>,
        _format: crate::format::VideoFormat,
    ) -> std::result::Result<Self, String> {
        Err("NDI feature not enabled".to_string())
    }
}

/// NDI source stub (NDI feature disabled)
#[cfg(not(feature = "ndi"))]
#[derive(Debug, Clone)]
pub struct NdiSource {
    /// Source name
    pub name: String,
    /// Source URL
    pub url_address: Option<String>,
}
