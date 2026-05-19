use crate::i18n::LocaleManager;
use crate::icons::IconManager;
use egui::Ui;
use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use super::types::{
    MediaBrowserAction, MediaEntry, MediaFolders, MediaType, SortMode, ThumbnailHandle, ViewMode,
};
use super::ui::render_ui;

/// Media browser state
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
    pub(crate) scan_tasks_active: Arc<std::sync::atomic::AtomicUsize>,
    /// Receiver for directory scan results
    pub(crate) scan_rx: std::sync::mpsc::Receiver<(PathBuf, Vec<MediaEntry>)>,
    /// Sender for directory scan results
    pub(crate) scan_tx: std::sync::mpsc::Sender<(PathBuf, Vec<MediaEntry>)>,
    /// Show folder settings
    pub(crate) show_folder_settings: bool,
}

impl MediaBrowser {
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
        browser.refresh();
        browser
    }

    pub fn refresh(&mut self) {
        self.scan_tasks_active.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.entries.clear();

        let path = self.current_dir.clone();
        let show_hidden = self.show_hidden;
        let tx = self.scan_tx.clone();
        let scan_tasks_active = self.scan_tasks_active.clone();

        rayon::spawn(move || {
            let mut entries = Vec::new();
            if let Ok(dir_entries) = std::fs::read_dir(&path) {
                for entry in dir_entries.flatten() {
                    if let Ok(metadata) = entry.metadata() {
                        if metadata.is_file() {
                            let entry_path = entry.path();
                            let name = entry.file_name().to_string_lossy().to_string();

                            if !show_hidden && name.starts_with('.') {
                                continue;
                            }

                            let file_type = entry_path
                                .extension()
                                .and_then(|e| e.to_str())
                                .map(MediaType::from_extension)
                                .unwrap_or(MediaType::Unknown);

                            if matches!(
                                file_type,
                                MediaType::Video
                                    | MediaType::Image
                                    | MediaType::ImageSequence
                                    | MediaType::Audio
                                    | MediaType::Hap
                            ) {
                                entries.push(MediaEntry {
                                    path: entry_path,
                                    name: name.clone(),
                                    name_lower: name.to_lowercase(),
                                    file_type,
                                    size_bytes: metadata.len(),
                                    duration_secs: None,
                                    thumbnail: None,
                                    color_tag: None,
                                    tags: Vec::new(),
                                    tags_lower: Vec::new(),
                                });
                            }
                        }
                    }
                }
            }

            scan_tasks_active.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
            let _ = tx.send((path, entries));
        });
    }

    pub fn process_scans(&mut self) {
        let mut latest_scan = None;
        while let Ok((path, entries)) = self.scan_rx.try_recv() {
            if path == self.current_dir {
                latest_scan = Some(entries);
            }
        }

        if let Some(mut entries) = latest_scan {
            for entry in &mut entries {
                entry.thumbnail = self.get_or_generate_thumbnail(&entry.path);

                if matches!(entry.file_type, MediaType::Video | MediaType::Audio | MediaType::Hap) {
                    let mut extracting = self.extracting_metadata.write();
                    if !extracting.contains(&entry.path) {
                        extracting.insert(entry.path.clone());
                        let tx = self.metadata_tx.clone();
                        let path_clone = entry.path.clone();
                        rayon::spawn(move || {
                            let duration = vorce_media::get_media_duration_secs(&path_clone);
                            let _ = tx.send((path_clone, duration));
                        });
                    }
                }
            }

            self.entries = entries;
            self.sort_entries();
        }
    }

    pub(crate) fn rebuild_index_map(&mut self) {
        self.path_to_index.clear();
        for (i, entry) in self.entries.iter().enumerate() {
            self.path_to_index.insert(entry.path.clone(), i);
        }
    }

    pub(crate) fn sort_entries(&mut self) {
        match self.sort_mode {
            SortMode::Name => self.entries.sort_by(|a, b| a.name.cmp(&b.name)),
            SortMode::Type => self.entries.sort_by_key(|e| e.file_type as u8),
            SortMode::Size => self.entries.sort_by_key(|e| e.size_bytes),
            SortMode::DateModified => {}
        }
        self.rebuild_index_map();
    }

    pub(crate) fn get_or_generate_thumbnail(&self, path: &Path) -> Option<ThumbnailHandle> {
        if let Some(thumb) = self.thumbnail_cache.read().get(path) {
            return Some(thumb.clone());
        }

        let mut generating = self.generating_thumbnails.write();
        if generating.contains(path) {
            return None;
        }

        let file_type = path
            .extension()
            .and_then(|e| e.to_str())
            .map(MediaType::from_extension)
            .unwrap_or(MediaType::Unknown);

        if matches!(file_type, MediaType::Image) {
            generating.insert(path.to_path_buf());
            let tx = self.thumbnail_tx.clone();
            let path_clone = path.to_path_buf();

            rayon::spawn(move || {
                let result = match image::open(&path_clone) {
                    Ok(img) => {
                        let thumbnail = img.thumbnail(128, 128);
                        let size = [thumbnail.width() as _, thumbnail.height() as _];
                        let rgba = thumbnail.to_rgba8();
                        Ok(egui::ColorImage::from_rgba_unmultiplied(
                            size,
                            rgba.as_flat_samples().as_slice(),
                        ))
                    }
                    Err(e) => Err(e.to_string()),
                };
                let _ = tx.send((path_clone, result));
            });
        }

        None
    }

    pub fn navigate_to(&mut self, path: PathBuf) {
        if path.is_dir() {
            self.current_dir = path.clone();
            self.path_input = path.display().to_string();
            self.refresh();

            self.history.truncate(self.history_index + 1);
            self.history.push(path);
            self.history_index = self.history.len() - 1;
        }
    }

    pub fn navigate_back(&mut self) {
        if self.history_index > 0 {
            self.history_index -= 1;
            self.current_dir = self.history[self.history_index].clone();
            self.path_input = self.current_dir.display().to_string();
            self.refresh();
        }
    }

    pub fn navigate_forward(&mut self) {
        if self.history_index < self.history.len() - 1 {
            self.history_index += 1;
            self.current_dir = self.history[self.history_index].clone();
            self.path_input = self.current_dir.display().to_string();
            self.refresh();
        }
    }

    pub fn navigate_up(&mut self) {
        if let Some(parent) = self.current_dir.parent() {
            self.navigate_to(parent.to_path_buf());
        }
    }

    pub(crate) fn filtered_entries(&self) -> Vec<(usize, &MediaEntry)> {
        self.entries
            .iter()
            .enumerate()
            .filter(|(_, entry)| {
                if let Some(filter) = self.filter_type {
                    if entry.file_type != filter {
                        return false;
                    }
                }

                if let Some(q) = &self.search_query_lower {
                    if !entry.name_lower.contains(q)
                        && !entry.tags_lower.iter().any(|t| t.contains(q))
                    {
                        return false;
                    }
                }

                true
            })
            .collect()
    }

    pub fn process_metadata(&mut self, _ctx: &egui::Context) {
        while let Ok((path, duration)) = self.metadata_rx.try_recv() {
            self.extracting_metadata.write().remove(&path);
            if let Some(dur) = duration {
                if let Some(&idx) = self.path_to_index.get(&path) {
                    if let Some(entry) = self.entries.get_mut(idx) {
                        if entry.path == path {
                            entry.duration_secs = Some(dur);
                        }
                    }
                }
            }
        }
    }

    pub fn process_thumbnails(&mut self, ctx: &egui::Context) {
        while let Ok((path, result)) = self.thumbnail_rx.try_recv() {
            if let Ok(color_image) = result {
                let size = (color_image.size[0] as u32, color_image.size[1] as u32);
                let texture = ctx.load_texture(
                    format!("thumb_{}", path.display()),
                    color_image,
                    egui::TextureOptions {
                        magnification: egui::TextureFilter::Linear,
                        minification: egui::TextureFilter::Linear,
                        wrap_mode: egui::TextureWrapMode::ClampToEdge,
                        mipmap_mode: None,
                    },
                );

                let handle = ThumbnailHandle { texture_handle: texture, size };

                if let Some(&idx) = self.path_to_index.get(&path) {
                    if let Some(entry) = self.entries.get_mut(idx) {
                        if entry.path == path {
                            entry.thumbnail = Some(handle.clone());
                        }
                    }
                }

                self.thumbnail_cache.write().insert(path.clone(), handle);
                ctx.request_repaint();
            }

            self.generating_thumbnails.write().remove(&path);
        }
    }

    pub fn ui(
        &mut self,
        ui: &mut Ui,
        locale: &LocaleManager,
        icons: Option<&IconManager>,
    ) -> Option<MediaBrowserAction> {
        render_ui(self, ui, locale, icons)
    }
}
