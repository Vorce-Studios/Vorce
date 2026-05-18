use super::models::{MediaEntry, MediaType, ThumbnailHandle, SortMode};
use super::state::MediaBrowserState;
use std::path::Path;

pub fn refresh_dir(state: &mut MediaBrowserState) {
    state.scan_tasks_active.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    state.entries.clear();

    let path = state.current_dir.clone();
    let show_hidden = state.show_hidden;
    let tx = state.scan_tx.clone();
    let scan_tasks_active = state.scan_tasks_active.clone();

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
                            MediaType::Video | MediaType::Image | MediaType::ImageSequence | MediaType::Audio | MediaType::Hap
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

pub fn process_scans(state: &mut MediaBrowserState) {
    let mut latest_scan = None;
    while let Ok((path, entries)) = state.scan_rx.try_recv() {
        if path == state.current_dir {
            latest_scan = Some(entries);
        }
    }

    if let Some(mut entries) = latest_scan {
        for entry in &mut entries {
            entry.thumbnail = get_or_generate_thumbnail(state, &entry.path);
            if matches!(entry.file_type, MediaType::Video | MediaType::Audio | MediaType::Hap) {
                let mut extracting = state.extracting_metadata.write();
                if !extracting.contains(&entry.path) {
                    extracting.insert(entry.path.clone());
                    let tx = state.metadata_tx.clone();
                    let path_clone = entry.path.clone();
                    rayon::spawn(move || {
                        let duration = vorce_media::get_media_duration_secs(&path_clone);
                        let _ = tx.send((path_clone, duration));
                    });
                }
            }
        }
        state.entries = entries;
        sort_entries(state);
    }
}

pub fn sort_entries(state: &mut MediaBrowserState) {
    match state.sort_mode {
        SortMode::Name => state.entries.sort_by(|a, b| a.name.cmp(&b.name)),
        SortMode::Type => state.entries.sort_by_key(|e| e.file_type as u8),
        SortMode::Size => state.entries.sort_by_key(|e| e.size_bytes),
        SortMode::DateModified => {}
    }
    state.path_to_index.clear();
    for (i, entry) in state.entries.iter().enumerate() {
        state.path_to_index.insert(entry.path.clone(), i);
    }
}

pub fn get_or_generate_thumbnail(state: &MediaBrowserState, path: &Path) -> Option<ThumbnailHandle> {
    if let Some(thumb) = state.thumbnail_cache.read().get(path) {
        return Some(thumb.clone());
    }
    let mut generating = state.generating_thumbnails.write();
    if generating.contains(path) {
        return None;
    }
    let file_type = path.extension().and_then(|e| e.to_str()).map(MediaType::from_extension).unwrap_or(MediaType::Unknown);
    if matches!(file_type, MediaType::Image) {
        generating.insert(path.to_path_buf());
        let tx = state.thumbnail_tx.clone();
        let path_clone = path.to_path_buf();
        rayon::spawn(move || {
            let result = match image::open(&path_clone) {
                Ok(img) => {
                    let thumbnail = img.thumbnail(128, 128);
                    let size = [thumbnail.width() as _, thumbnail.height() as _];
                    let rgba = thumbnail.to_rgba8();
                    Ok(egui::ColorImage::from_rgba_unmultiplied(size, rgba.as_flat_samples().as_slice()))
                }
                Err(e) => Err(e.to_string()),
            };
            let _ = tx.send((path_clone, result));
        });
    }
    None
}
