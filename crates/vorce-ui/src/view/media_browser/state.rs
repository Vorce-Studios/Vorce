use super::models::*;
use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

pub struct MediaBrowserState {
    pub current_dir: PathBuf,
    pub path_input: String,
    pub entries: Vec<MediaEntry>,
    pub search_query: String,
    pub search_query_lower: Option<String>,
    pub filter_type: Option<MediaType>,
    pub view_mode: ViewMode,
    pub thumbnail_size: f32,
    pub selected: Option<usize>,
    pub hovered: Option<usize>,
    pub hover_start: Option<Instant>,
    pub preview_delay: f32,
    pub thumbnail_cache: Arc<RwLock<HashMap<PathBuf, ThumbnailHandle>>>,
    pub thumbnail_rx: std::sync::mpsc::Receiver<(PathBuf, Result<egui::ColorImage, String>)>,
    pub thumbnail_tx: std::sync::mpsc::Sender<(PathBuf, Result<egui::ColorImage, String>)>,
    pub metadata_rx: std::sync::mpsc::Receiver<(PathBuf, Option<f32>)>,
    pub metadata_tx: std::sync::mpsc::Sender<(PathBuf, Option<f32>)>,
    pub extracting_metadata: Arc<RwLock<HashSet<PathBuf>>>,
    pub generating_thumbnails: Arc<RwLock<HashSet<PathBuf>>>,
    pub path_to_index: HashMap<PathBuf, usize>,
    pub show_hidden: bool,
    pub sort_mode: SortMode,
    pub history: Vec<PathBuf>,
    pub history_index: usize,
    pub media_folders: MediaFolders,
    pub scan_tasks_active: Arc<std::sync::atomic::AtomicUsize>,
    pub scan_rx: std::sync::mpsc::Receiver<(PathBuf, Vec<MediaEntry>)>,
    pub scan_tx: std::sync::mpsc::Sender<(PathBuf, Vec<MediaEntry>)>,
    pub show_folder_settings: bool,
}

impl MediaBrowserState {
    pub fn new(initial_dir: PathBuf) -> Self {
        let (tx, rx) = std::sync::mpsc::channel();
        let (metadata_tx, metadata_rx) = std::sync::mpsc::channel();
        let (scan_tx, scan_rx) = std::sync::mpsc::channel();
        let path_str = initial_dir.display().to_string();

        let mut browser = Self {
            current_dir: initial_dir.clone(),
            path_input: path_str,
            entries: Vec::new(),
            search_query: String::new(),
            search_query_lower: None,
            filter_type: None,
            view_mode: ViewMode::Grid,
            thumbnail_size: 80.0,
            selected: None,
            hovered: None,
            hover_start: None,
            preview_delay: 0.5,
            thumbnail_cache: Arc::new(RwLock::new(HashMap::new())),
            thumbnail_rx: rx,
            thumbnail_tx: tx,
            generating_thumbnails: Arc::new(RwLock::new(HashSet::new())),
            metadata_rx,
            metadata_tx,
            extracting_metadata: Arc::new(RwLock::new(HashSet::new())),
            path_to_index: HashMap::new(),
            show_hidden: false,
            sort_mode: SortMode::Name,
            history: vec![initial_dir.clone()],
            history_index: 0,
            scan_tasks_active: Arc::new(std::sync::atomic::AtomicUsize::new(0)),
            scan_rx,
            scan_tx,
            media_folders: MediaFolders {
                video_folder: initial_dir.clone(),
                image_folder: initial_dir.clone(),
                audio_folder: initial_dir.clone(),
                default_folder: initial_dir,
            },
            show_folder_settings: false,
        };
        super::scan::refresh_dir(&mut browser);
        browser
    }

    pub fn filtered_entries(&self) -> Vec<(usize, &MediaEntry)> {
        self.entries.iter().enumerate().filter(|(_, entry)| {
            if let Some(filter) = self.filter_type {
                if entry.file_type != filter { return false; }
            }
            if let Some(q) = &self.search_query_lower {
                if !entry.name_lower.contains(q) && !entry.tags_lower.iter().any(|t| t.contains(q)) {
                    return false;
                }
            }
            true
        }).collect()
    }
}
