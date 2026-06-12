use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use super::types::*;
use super::MediaBrowser;

/// Media browser state
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
            thumbnail_size: 80.0, // Reduced from 120 for compact view
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

    /// Refresh the file list
    pub fn refresh(&mut self) {
        // Prevent concurrent scans of the same or different directories if one is already running
        // Or we could just let them run and overwrite. We'll set the flag.
        self.scan_tasks_active.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.entries.clear();

        let path = self.current_dir.clone();
        let show_hidden = self.show_hidden;
        let tx = self.scan_tx.clone();
        let scan_tasks_active = self.scan_tasks_active.clone();

        // These are needed for get_or_generate_thumbnail logic inside the background thread
        // Wait, getting thumbnails also accesses self.thumbnail_cache and self.generating_thumbnails,
        // which are Arc<RwLock>. We can just skip thumbnail generation in the background thread
        // and do it in the main thread when we receive the entries.
        // That avoids sending Arcs to the background thread unnecessarily.

        rayon::spawn(move || {
            let mut entries = Vec::new();
            if let Ok(dir_entries) = std::fs::read_dir(&path) {
                for entry in dir_entries.flatten() {
                    if let Ok(metadata) = entry.metadata() {
                        if metadata.is_file() {
                            let entry_path = entry.path();
                            let name = entry.file_name().to_string_lossy().to_string();

                            // Skip hidden files if not showing them
                            if !show_hidden && name.starts_with('.') {
                                continue;
                            }

                            let file_type = entry_path
                                .extension()
                                .and_then(|e| e.to_str())
                                .map(MediaType::from_extension)
                                .unwrap_or(MediaType::Unknown);

                            // Only include media files
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
                                    thumbnail: None, // Will be populated in main thread
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

    /// Process directory scan results
    pub fn process_scans(&mut self) {
        // Only process the latest scan if there are multiple in the queue
        let mut latest_scan = None;
        while let Ok((path, entries)) = self.scan_rx.try_recv() {
            // Only accept scan results for the current directory
            // (in case we navigated away before the scan finished)
            if path == self.current_dir {
                latest_scan = Some(entries);
            }
        }

        if let Some(mut entries) = latest_scan {
            // Now that we have the entries on the main thread,
            // trigger thumbnail generation and metadata extraction
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

    /// Rebuild the path-to-index map for O(1) lookups
    fn rebuild_index_map(&mut self) {
        self.path_to_index.clear();
        for (i, entry) in self.entries.iter().enumerate() {
            self.path_to_index.insert(entry.path.clone(), i);
        }
    }

    /// Sort entries based on sort mode
    fn sort_entries(&mut self) {
        match self.sort_mode {
            SortMode::Name => self.entries.sort_by(|a, b| a.name.cmp(&b.name)),
            SortMode::Type => self.entries.sort_by_key(|e| e.file_type as u8),
            SortMode::Size => self.entries.sort_by_key(|e| e.size_bytes),
            SortMode::DateModified => {
                // Would need to store modification time
            }
        }
        self.rebuild_index_map();
    }

    /// Get or generate thumbnail for a file
    fn get_or_generate_thumbnail(&self, path: &Path) -> Option<ThumbnailHandle> {
        // Check cache first
        if let Some(thumb) = self.thumbnail_cache.read().get(path) {
            return Some(thumb.clone());
        }

        // Check if already generating
        let mut generating = self.generating_thumbnails.write();
        if generating.contains(path) {
            return None;
        }

        let file_type = path
            .extension()
            .and_then(|e| e.to_str())
            .map(MediaType::from_extension)
            .unwrap_or(MediaType::Unknown);

        // Generate thumbnail in background for supported media types
        if matches!(file_type, MediaType::Image) {
            generating.insert(path.to_path_buf());
            let tx = self.thumbnail_tx.clone();
            let path_clone = path.to_path_buf();

            rayon::spawn(move || {
                let result = match image::open(&path_clone) {
                    Ok(img) => {
                        let thumbnail = img.thumbnail(128, 128); // Standard thumbnail size
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

    /// Navigate to a directory
    pub fn navigate_to(&mut self, path: PathBuf) {
        if path.is_dir() {
            self.current_dir = path.clone();
            self.path_input = path.display().to_string();
            self.refresh();

            // Update history
            self.history.truncate(self.history_index + 1);
            self.history.push(path);
            self.history_index = self.history.len() - 1;
        }
    }

    /// Navigate back in history
    pub fn navigate_back(&mut self) {
        if self.history_index > 0 {
            self.history_index -= 1;
            self.current_dir = self.history[self.history_index].clone();
            self.path_input = self.current_dir.display().to_string();
            self.refresh();
        }
    }

    /// Navigate forward in history
    pub fn navigate_forward(&mut self) {
        if self.history_index < self.history.len() - 1 {
            self.history_index += 1;
            self.current_dir = self.history[self.history_index].clone();
            self.path_input = self.current_dir.display().to_string();
            self.refresh();
        }
    }

    /// Navigate to parent directory
    pub fn navigate_up(&mut self) {
        if let Some(parent) = self.current_dir.parent() {
            self.navigate_to(parent.to_path_buf());
        }
    }

    /// Get filtered and searched entries
    pub(crate) fn filtered_entries(&self) -> Vec<(usize, &MediaEntry)> {
        self.entries
            .iter()
            .enumerate()
            .filter(|(_, entry)| {
                // Filter by type
                if let Some(filter) = self.filter_type {
                    if entry.file_type != filter {
                        return false;
                    }
                }

                // Filter by search query
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

    /// Render the media browser UI
    /// Process completed thumbnails and clear flags
    /// Process completed metadata extraction and clear flags
    pub fn process_metadata(&mut self, _ctx: &egui::Context) {
        while let Ok((path, duration)) = self.metadata_rx.try_recv() {
            self.extracting_metadata.write().remove(&path);
            if let Some(dur) = duration {
                // O(1) update using index map
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

                // O(1) update using index map
                if let Some(&idx) = self.path_to_index.get(&path) {
                    if let Some(entry) = self.entries.get_mut(idx) {
                        if entry.path == path {
                            entry.thumbnail = Some(handle.clone());
                        }
                    }
                }

                self.thumbnail_cache.write().insert(path.clone(), handle);

                // Trigger a UI update to reflect the new thumbnail
                ctx.request_repaint();
            }

            // Remove from generating set
            self.generating_thumbnails.write().remove(&path);
        }
    }
}
