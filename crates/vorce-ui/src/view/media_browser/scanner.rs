//! Media Browser Scanner

use super::data::{MediaEntry, MediaType};
use std::path::Path;

pub struct Scanner;

impl Scanner {
    pub fn scan_directory(path: &Path, show_hidden: bool) -> Vec<MediaEntry> {
        let mut entries = Vec::new();
        if let Ok(dir_entries) = std::fs::read_dir(path) {
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
        entries
    }
}
