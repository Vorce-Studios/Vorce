mod state;
mod types;
mod ui;

use egui;
use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
pub use types::*;

pub struct MediaBrowser {
    /// Current directory
    pub(crate) current_dir: PathBuf,
    /// Path input for editing
    pub(crate) path_input: String,
    /// Media entries in current directory
    pub(crate) entries: Vec<MediaEntry>,
    /// Search query
    pub(crate) search_query: String,
    /// Cached lowercased search query to prevent per-frame allocation
    pub(crate) search_query_lower: Option<String>,
    /// Filter by type
    pub(crate) filter_type: Option<MediaType>,
    /// View mode
    pub(crate) view_mode: ViewMode,
    /// Thumbnail size in pixels
    pub(crate) thumbnail_size: f32,
    /// Selected entry index
    pub(crate) selected: Option<usize>,
    /// Hovered entry (for preview)
    pub(crate) hovered: Option<usize>,
    /// Hover start time (for delayed preview)
    pub(crate) hover_start: Option<Instant>,
    /// Preview delay in seconds
    pub(crate) preview_delay: f32,
    /// Thumbnail cache
    pub(crate) thumbnail_cache: Arc<RwLock<HashMap<PathBuf, ThumbnailHandle>>>,
    /// Receiver for generated thumbnails
    pub(crate) thumbnail_rx: std::sync::mpsc::Receiver<(PathBuf, Result<egui::ColorImage, String>)>,
    /// Sender for generated thumbnails
    pub(crate) thumbnail_tx: std::sync::mpsc::Sender<(PathBuf, Result<egui::ColorImage, String>)>,
    /// Receiver for extracted metadata
    pub(crate) metadata_rx: std::sync::mpsc::Receiver<(PathBuf, Option<f32>)>,
    /// Sender for extracted metadata
    pub(crate) metadata_tx: std::sync::mpsc::Sender<(PathBuf, Option<f32>)>,
    /// Currently extracting metadata
    pub(crate) extracting_metadata: Arc<RwLock<HashSet<PathBuf>>>,
    /// Currently generating thumbnails
    pub(crate) generating_thumbnails: Arc<RwLock<HashSet<PathBuf>>>,
    /// Map of path to index in entries for O(1) lookup
    pub(crate) path_to_index: HashMap<PathBuf, usize>,
    /// Show hidden files
    pub(crate) show_hidden: bool,
    /// Sort mode
    pub(crate) sort_mode: SortMode,
    /// Directory history (for back/forward navigation)
    pub(crate) history: Vec<PathBuf>,
    pub(crate) history_index: usize,
    /// Media folders per type
    pub media_folders: MediaFolders,
    /// Active scan flag
    /// Active scan flag
    pub(crate) scan_tasks_active: Arc<std::sync::atomic::AtomicUsize>,
    /// Receiver for directory scan results
    pub(crate) scan_rx: std::sync::mpsc::Receiver<(PathBuf, Vec<MediaEntry>)>,
    /// Sender for directory scan results
    pub(crate) scan_tx: std::sync::mpsc::Sender<(PathBuf, Vec<MediaEntry>)>,
    /// Show folder settings
    pub(crate) show_folder_settings: bool,
}
