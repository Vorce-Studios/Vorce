use egui::Color32;
use std::path::PathBuf;

/// Media file entry in the browser
#[derive(Debug, Clone)]
pub struct MediaEntry {
    pub path: PathBuf,
    pub name: String,
    pub name_lower: String,
    pub file_type: MediaType,
    pub size_bytes: u64,
    pub duration_secs: Option<f32>,
    pub thumbnail: Option<ThumbnailHandle>,
    pub color_tag: Option<Color32>,
    pub tags: Vec<String>,
    pub tags_lower: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaType {
    Video, Image, ImageSequence, Audio, Hap, Unknown,
}

impl MediaType {
    pub fn from_extension(ext: &str) -> Self {
        match ext.to_lowercase().as_str() {
            "mp4" | "avi" | "mpeg" | "mpg" | "mkv" | "webm" => Self::Video,
            "mov" => Self::Video,
            "png" | "jpg" | "jpeg" | "tiff" | "tif" | "bmp" | "dds" => Self::Image,
            "gif" => Self::ImageSequence,
            "wav" | "mp3" | "aac" | "flac" | "ogg" => Self::Audio,
            _ => Self::Unknown,
        }
    }

    pub fn icon(&self) -> &'static str {
        match self {
            Self::Video => "🎬",
            Self::Image => "🖼",
            Self::ImageSequence => "🎞",
            Self::Audio => "🎵",
            Self::Hap => "⚡",
            Self::Unknown => "📄",
        }
    }

    pub fn app_icon(&self) -> Option<crate::icons::AppIcon> {
        match self {
            Self::Video => Some(crate::icons::AppIcon::VideoFile),
            Self::Image => Some(crate::icons::AppIcon::ImageFile),
            Self::ImageSequence => Some(crate::icons::AppIcon::VideoFile),
            Self::Audio => Some(crate::icons::AppIcon::AudioFile),
            Self::Hap => Some(crate::icons::AppIcon::VideoPlayer),
            Self::Unknown => None,
        }
    }
}

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
pub enum ViewMode { Grid, List }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortMode { Name, Type, Size, DateModified }

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

#[derive(Debug, Clone)]
pub enum MediaBrowserAction {
    FileSelected(PathBuf),
    FileDoubleClicked(PathBuf),
    StartPreview(PathBuf),
    StopPreview,
}
