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
use crate::format::{FrameData, PixelFormat as VorcePixelFormat, VideoFormat, VideoFrame};
#[cfg(feature = "ndi")]
use crate::source::VideoSource;

#[cfg(feature = "ndi")]
use grafton_ndi::{
    Finder, FinderOptions, PixelFormat as NdiPixelFormat, Receiver, ReceiverBandwidth,
    ReceiverColorFormat, ReceiverOptions, Sender, SenderOptions, VideoFrameBuilder, NDI,
};
#[cfg(feature = "ndi")]
use std::sync::{Arc, Mutex};
#[cfg(feature = "ndi")]
use std::time::Duration;
#[cfg(feature = "ndi")]
use tracing::{error, info};

/// Re-export Source type for external use
#[cfg(feature = "ndi")]
pub use grafton_ndi::Source;

/// Wrapper for NDI Source that is Send + Sync safe
#[cfg(feature = "ndi")]
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct NdiSource {
    /// The name of the NDI source
    pub name: String,
    /// The URL/address of the source (if available)
    pub address: Option<String>,
}

#[cfg(feature = "ndi")]
impl From<grafton_ndi::Source> for NdiSource {
    fn from(source: grafton_ndi::Source) -> Self {
        Self { name: source.name.clone(), address: Some(format!("{:?}", source.address)) }
    }
}

/// NDI library handle - ensures NDI is initialized
#[cfg(feature = "ndi")]
pub struct NdiHandle {
    ndi: Arc<NDI>,
}

#[cfg(feature = "ndi")]
impl NdiHandle {
    /// Creates a new NDI handle.
    pub fn new() -> Result<Self> {
        let ndi = NDI::new().map_err(|e| {
            error!("Failed to initialize NDI library: {}", e);
            IoError::NdiError(format!("Failed to initialize NDI: {}", e))
        })?;
        info!("NDI library initialized successfully");
        Ok(Self { ndi: Arc::new(ndi) })
    }
}

/// NDI receiver host for capturing video from NDI sources in a thread-safe way.
#[cfg(feature = "ndi")]
pub struct NdiReceiver {
    name: String,
    source_info: Option<NdiSource>,
    format: Arc<Mutex<VideoFormat>>,
    frame_count: Arc<std::sync::atomic::AtomicU64>,
    receiver_tx: std::sync::mpsc::Sender<ReceiverCommand>,
    frame_rx: std::sync::mpsc::Receiver<VideoFrame>,
    is_available: Arc<std::sync::atomic::AtomicBool>,
}

#[cfg(feature = "ndi")]
enum ReceiverCommand {
    Connect(NdiSource),
    Stop,
}

#[cfg(feature = "ndi")]
impl NdiReceiver {
    /// Creates a new NDI receiver.
    pub fn new() -> Result<Self> {
        info!("Creating NDI Receiver Host");
        let (receiver_tx, receiver_rx) = std::sync::mpsc::channel();
        let (frame_tx, frame_rx) = std::sync::mpsc::channel();

        let format = Arc::new(Mutex::new(VideoFormat::hd_1080p30_rgba()));
        let frame_count = Arc::new(std::sync::atomic::AtomicU64::new(0));
        let is_available = Arc::new(std::sync::atomic::AtomicBool::new(true));

        let format_clone = format.clone();
        let frame_count_clone = frame_count.clone();
        let is_available_clone = is_available.clone();

        std::thread::spawn(move || {
            let handle = match NdiHandle::new() {
                Ok(h) => h,
                Err(e) => {
                    error!("NDI Receiver thread failed to initialize: {}", e);
                    is_available_clone.store(false, std::sync::atomic::Ordering::SeqCst);
                    return;
                }
            };

            let mut receiver: Option<Receiver> = None;

            loop {
                // Handle commands
                while let Ok(cmd) = receiver_rx.try_recv() {
                    match cmd {
                        ReceiverCommand::Connect(source) => {
                            info!("NDI Receiver connecting to {}", source.name);
                            match Self::internal_connect(&handle.ndi, &source) {
                                Ok(r) => {
                                    receiver = Some(r);
                                    info!("NDI Receiver connected to {}", source.name);
                                }
                                Err(e) => {
                                    error!("NDI Receiver connection failed: {}", e);
                                }
                            }
                        }
                        ReceiverCommand::Stop => return,
                    }
                }

                // Poll for frames if connected
                if let Some(ref r) = receiver {
                    match r.capture_video(Duration::from_millis(16)) {
                        Ok(v) => {
                            let width = v.width as u32;
                            let height = v.height as u32;
                            let fr = v.frame_rate_n as f32 / v.frame_rate_d.max(1) as f32;

                            let data = v.data.clone();
                            let video_format = VideoFormat {
                                width,
                                height,
                                pixel_format: VorcePixelFormat::BGRA8,
                                frame_rate: fr,
                            };

                            {
                                let mut fmt =
                                    format_clone.lock().unwrap_or_else(|e| e.into_inner());
                                *fmt = video_format.clone();
                            }

                            let frame = VideoFrame {
                                data: FrameData::Cpu(Arc::new(data)),
                                format: video_format,
                                timestamp: Duration::from_nanos(v.timestamp as u64),
                                metadata: Default::default(),
                            };

                            let _ = frame_tx.send(frame);
                            frame_count_clone.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                        }
                        Err(_e) => {
                            // Skip errors (timeout etc)
                        }
                    }
                } else {
                    std::thread::sleep(Duration::from_millis(100));
                }
            }
        });

        Ok(Self {
            name: "NDI Receiver".to_string(),
            source_info: None,
            format,
            frame_count,
            receiver_tx,
            frame_rx,
            is_available,
        })
    }

    fn internal_connect(ndi: &NDI, source: &NdiSource) -> Result<Receiver> {
        let finder_options = FinderOptions::builder().show_local_sources(true).build();
        let finder =
            Finder::new(ndi, &finder_options).map_err(|e| IoError::NdiError(e.to_string()))?;

        let sources = finder
            .find_sources(Duration::from_secs(2))
            .map_err(|e| IoError::NdiError(e.to_string()))?;

        let matching_source = sources
            .into_iter()
            .find(|s| s.name == source.name)
            .ok_or_else(|| IoError::NdiError(format!("Source '{}' not found", source.name)))?;

        let options = ReceiverOptions::builder(matching_source)
            .color(ReceiverColorFormat::BGRX_BGRA)
            .bandwidth(ReceiverBandwidth::Highest)
            .name(format!("Vorce-{}", source.name))
            .build();

        Receiver::new(ndi, &options).map_err(|e| IoError::NdiError(e.to_string()))
    }

    /// Discovers available NDI sources on the network.
    pub fn discover_sources(timeout_ms: u32) -> Result<Vec<NdiSource>> {
        info!("Starting NDI source discovery for {}ms", timeout_ms);

        let handle = NdiHandle::new()?;
        let finder_options = FinderOptions::builder().show_local_sources(true).build();
        let finder = Finder::new(&handle.ndi, &finder_options)
            .map_err(|e| IoError::NdiError(e.to_string()))?;

        let sources = finder
            .find_sources(Duration::from_millis(timeout_ms as u64))
            .map_err(|e| IoError::NdiError(e.to_string()))?;
        Ok(sources.into_iter().map(|s| s.into()).collect())
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
        self.source_info = Some(source.clone());
        self.receiver_tx
            .send(ReceiverCommand::Connect(source.clone()))
            .map_err(|_| IoError::NdiError("Receiver thread disconnected".to_string()))
    }

    /// Returns the name of the connected source, if any.
    pub fn source_name(&self) -> Option<&str> {
        self.source_info.as_ref().map(|s| s.name.as_str())
    }

    /// Returns whether a source is connected.
    pub fn is_connected(&self) -> bool {
        self.source_info.is_some()
    }
}

#[cfg(feature = "ndi")]
impl VideoSource for NdiReceiver {
    fn name(&self) -> &str {
        &self.name
    }

    fn format(&self) -> VideoFormat {
        self.format.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    fn receive_frame(&mut self) -> Result<VideoFrame> {
        self.frame_rx.try_recv().map_err(|_| IoError::NoFrameAvailable)
    }

    fn is_available(&self) -> bool {
        self.is_available.load(std::sync::atomic::Ordering::SeqCst)
    }

    fn frame_count(&self) -> u64 {
        self.frame_count.load(std::sync::atomic::Ordering::SeqCst)
    }
}

#[cfg(feature = "ndi")]
impl Drop for NdiReceiver {
    fn drop(&mut self) {
        let _ = self.receiver_tx.send(ReceiverCommand::Stop);
    }
}

#[cfg(feature = "ndi")]
impl Default for NdiReceiver {
    fn default() -> Self {
        Self::new().unwrap_or_else(|e| {
            error!("Failed to create default NDI receiver: {}", e);
            let (tx, _) = std::sync::mpsc::channel();
            let (_, rx) = std::sync::mpsc::channel();
            Self {
                name: "NDI Receiver (Failed)".to_string(),
                source_info: None,
                format: Arc::new(Mutex::new(VideoFormat::hd_1080p30_rgba())),
                frame_count: Arc::new(std::sync::atomic::AtomicU64::new(0)),
                receiver_tx: tx,
                frame_rx: rx,
                is_available: Arc::new(std::sync::atomic::AtomicBool::new(false)),
            }
        })
    }
}

/// NDI sender for broadcasting video to the network.
#[cfg(feature = "ndi")]
pub struct NdiSender {
    _handle: NdiHandle,
    name: String,
    _format: VideoFormat,
    frame_count: u64,
    sender: Sender,
}

#[cfg(feature = "ndi")]
impl NdiSender {
    /// Creates a new NDI sender with the given name.
    pub fn new(name: impl Into<String>, format: VideoFormat) -> Result<Self> {
        let name = name.into();
        info!("Creating NDI Sender: {}", name);

        let handle = NdiHandle::new()?;
        let options = SenderOptions::builder(&name).build();

        let sender = Sender::new(&handle.ndi, &options).map_err(|e| {
            error!("Failed to create NDI sender: {}", e);
            IoError::NdiSenderFailed(format!("Failed to create sender: {}", e))
        })?;

        info!("NDI Sender '{}' created successfully", name);

        Ok(Self { _handle: handle, name, _format: format, frame_count: 0, sender })
    }

    /// Sends a video frame.
    pub fn send_frame(&mut self, frame: &VideoFrame) -> Result<()> {
        let data = match &frame.data {
            FrameData::Cpu(data) => data,
            FrameData::Gpu(_) => {
                return Err(IoError::NdiSenderFailed(
                    "GPU frames must be downloaded to CPU before sending".to_string(),
                ));
            }
        };

        let mut ndi_frame = VideoFrameBuilder::new()
            .resolution(frame.format.width as i32, frame.format.height as i32)
            .pixel_format(NdiPixelFormat::BGRA)
            .frame_rate(frame.format.frame_rate as i32, 1)
            .build()
            .map_err(|e| IoError::NdiSenderFailed(format!("Failed to build NDI frame: {}", e)))?;

        ndi_frame.data = data.as_slice().to_vec();

        self.sender.send_video(&ndi_frame);

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
/// Stub implementation of NDI receiver when the feature is disabled.
#[cfg(not(feature = "ndi"))]
/// Stub NDI Receiver for when the 'ndi' feature is disabled.
pub struct NdiReceiver;

#[cfg(not(feature = "ndi"))]
impl NdiReceiver {
    /// Creates a new NDI receiver (always returns an error when NDI is disabled).
    pub fn new() -> std::result::Result<Self, String> {
        Err("NDI feature not enabled".to_string())
    }

    /// Stub connect method.
    pub fn connect(&mut self, _source: &NdiSource) -> std::result::Result<(), String> {
        Err("NDI feature not enabled".to_string())
    }

    /// Stub source_name method.
    pub fn source_name(&self) -> Option<&str> {
        None
    }

    /// Stub receive_frame method.
    pub fn receive_frame(&mut self) -> std::result::Result<crate::format::VideoFrame, String> {
        Err("NDI feature not enabled".to_string())
    }
}

/// Stub implementation of NDI sender when the feature is disabled.
#[cfg(not(feature = "ndi"))]
pub struct NdiSender;

#[cfg(not(feature = "ndi"))]
impl NdiSender {
    /// Creates a new NDI sender (always returns an error when NDI is disabled).
    pub fn new(
        _name: impl Into<String>,
        _format: crate::format::VideoFormat,
    ) -> std::result::Result<Self, String> {
        Err("NDI feature not enabled".to_string())
    }

    /// Stub send_frame method.
    pub fn send_frame(
        &mut self,
        _frame: &crate::format::VideoFrame,
    ) -> std::result::Result<(), String> {
        Err("NDI feature not enabled".to_string())
    }

    /// Stub name method.
    pub fn name(&self) -> &str {
        "NDI Stub"
    }
}

/// Data structure representing an NDI source (stub when feature is disabled).
#[cfg(not(feature = "ndi"))]
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct NdiSource {
    /// The name of the NDI source.
    pub name: String,
    /// The URL/address of the source.
    pub address: Option<String>,
}
