use crate::icons::AppIcon;
use egui::Color32;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct MediaEntry {
    /// File system path to the asset or resource.
    pub path: PathBuf,
    /// Human-readable display name.
    pub name: String,
    /// Lowercased name for fast searching without allocation
    pub name_lower: String,
    pub file_type: MediaType,
    pub size_bytes: u64,
    pub duration_secs: Option<f32>,
    pub thumbnail: Option<ThumbnailHandle>,
    pub color_tag: Option<Color32>,
    pub tags: Vec<String>,
    /// Lowercased tags for fast searching without allocation
    pub tags_lower: Vec<String>,
}

/// Media type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaType {
    Video,
    Image,
    ImageSequence,
    Audio,
    /// HAP video (GPU-accelerated codec)
    Hap,
    Unknown,
}

impl MediaType {
    pub fn from_extension(ext: &str) -> Self {
        if ["mp4", "avi", "mpeg", "mpg", "mkv", "webm", "mov"]
            .iter()
            .any(|&s| ext.eq_ignore_ascii_case(s))
        {
            Self::Video
        } else if ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "dds"]
            .iter()
            .any(|&s| ext.eq_ignore_ascii_case(s))
        {
            Self::Image
        } else if ext.eq_ignore_ascii_case("gif") {
            Self::ImageSequence
        } else if ["wav", "mp3", "aac", "flac", "ogg"].iter().any(|&s| ext.eq_ignore_ascii_case(s))
        {
            Self::Audio
        } else {
            Self::Unknown
        }
    }

    pub fn icon(&self) -> &'static str {
        match self {
            Self::Video => "🎬",
            Self::Image => "🖼",
            Self::ImageSequence => "🎞",
            Self::Audio => "🎵",
            Self::Hap => "⚡", // Lightning for GPU-accelerated
            Self::Unknown => "📄",
        }
    }

    pub fn app_icon(&self) -> Option<AppIcon> {
        match self {
            Self::Video => Some(AppIcon::VideoFile),
            Self::Image => Some(AppIcon::ImageFile),
            Self::ImageSequence => Some(AppIcon::VideoFile),
            Self::Audio => Some(AppIcon::AudioFile),
            Self::Hap => Some(AppIcon::VideoPlayer), // Use VideoPlayer for HAP
            Self::Unknown => None,
        }
    }
}

/// Thumbnail handle (reference to generated thumbnail)
#[derive(Clone)]
pub struct ThumbnailHandle {
    pub texture_handle: egui::TextureHandle,
    pub size: (u32, u32),
}

impl std::fmt::Debug for ThumbnailHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ThumbnailHandle").field("size", &self.size).finish()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewMode {
    Grid,
    List,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortMode {
    Name,
    Type,
    Size,
    DateModified,
}

/// Media folder configuration per type
#[derive(Debug, Clone)]
pub struct MediaFolders {
    pub video_folder: PathBuf,
    pub image_folder: PathBuf,
    pub audio_folder: PathBuf,
    pub default_folder: PathBuf,
}

impl Default for MediaFolders {
    fn default() -> Self {
        let default = std::env::current_dir().unwrap_or_default();
        Self {
            video_folder: dirs::video_dir().unwrap_or(default.clone()),
            image_folder: dirs::picture_dir().unwrap_or(default.clone()),
            audio_folder: dirs::audio_dir().unwrap_or(default.clone()),
            default_folder: default,
        }
    }
}

/// Actions that can be triggered by the media browser
#[derive(Debug, Clone)]
pub enum MediaBrowserAction {
    FileSelected(PathBuf),
    FileDoubleClicked(PathBuf),
    StartPreview(PathBuf),
    StopPreview,
}
