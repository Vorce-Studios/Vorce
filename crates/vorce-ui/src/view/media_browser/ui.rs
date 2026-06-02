use super::models::*;
use super::state::MediaBrowserState;
use crate::i18n::LocaleManager;
use crate::icons::IconManager;
use egui::{Color32, Response, Sense, Ui, Vec2};
use std::path::PathBuf;
use std::time::Instant;

pub struct MediaBrowser {
    pub state: MediaBrowserState,
}

impl MediaBrowser {
    pub fn new(initial_dir: std::path::PathBuf) -> Self {
        Self { state: MediaBrowserState::new(initial_dir) }
    }

    pub fn navigate_to(&mut self, path: std::path::PathBuf) {
        super::history::navigate_to(&mut self.state, path);
    }

    pub fn refresh(&mut self) {
        super::scan::refresh_dir(&mut self.state);
    }

    pub fn process_metadata(&mut self, _ctx: &egui::Context) {
        while let Ok((path, duration)) = self.state.metadata_rx.try_recv() {
            self.state.extracting_metadata.write().remove(&path);
            if let Some(dur) = duration {
                if let Some(&idx) = self.state.path_to_index.get(&path) {
                    if let Some(entry) = self.state.entries.get_mut(idx) {
                        if entry.path == path {
                            entry.duration_secs = Some(dur);
                        }
                    }
                }
            }
        }
    }

    pub fn process_thumbnails(&mut self, ctx: &egui::Context) {
        while let Ok((path, result)) = self.state.thumbnail_rx.try_recv() {
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

                self.state.thumbnail_cache.write().insert(path.clone(), handle.clone());
                ctx.request_repaint();

                if let Some(&idx) = self.state.path_to_index.get(&path) {
                    if let Some(entry) = self.state.entries.get_mut(idx) {
                        if entry.path == path {
                            entry.thumbnail = Some(handle);
                        }
                    }
                }
            }
            self.state.generating_thumbnails.write().remove(&path);
        }
    }

    pub fn ui(
        &mut self,
        ui: &mut Ui,
        locale: &LocaleManager,
        icons: Option<&IconManager>,
    ) -> Option<MediaBrowserAction> {
        self.process_thumbnails(ui.ctx());
        self.process_metadata(ui.ctx());
        super::scan::process_scans(&mut self.state);

        let mut action = None;

        // Compact toolbar with navigation
        ui.horizontal(|ui| {
            // Navigation buttons (compact, icons only)
            ui.add_enabled_ui(self.state.history_index > 0, |ui| {
                if ui.button("◀").clone().on_hover_text(locale.t("media-browser-back")).clicked()
                {
                    super::history::navigate_back(&mut self.state);
                }
            });

            ui.add_enabled_ui(self.state.history_index < self.state.history.len() - 1, |ui| {
                if ui.button("▶").clone().on_hover_text(locale.t("media-browser-forward")).clicked()
                {
                    super::history::navigate_forward(&mut self.state);
                }
            });

            if ui.button("⬆").clone().on_hover_text(locale.t("media-browser-up")).clicked() {
                super::history::navigate_up(&mut self.state);
            }

            if ui.button("🔄").clone().on_hover_text(locale.t("media-browser-refresh")).clicked()
            {
                super::scan::refresh_dir(&mut self.state);
            }

            if ui.button("⚙").clone().on_hover_text("Folder Settings").clicked() {
                self.state.show_folder_settings = !self.state.show_folder_settings;
            }

            ui.separator();

            // Editable path input
            let path_response = ui.add(
                egui::TextEdit::singleline(&mut self.state.path_input)
                    .desired_width(ui.available_width() - 30.0)
                    .hint_text("Enter path..."),
            );

            if path_response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                let new_path = PathBuf::from(&self.state.path_input);
                if new_path.is_dir() {
                    super::history::navigate_to(&mut self.state, new_path);
                }
            }
        });

        // Folder Settings Panel (collapsible)
        if self.state.show_folder_settings {
            ui.group(|ui| {
                ui.label("📁 Media Folder Settings");
                ui.separator();

                ui.horizontal(|ui| {
                    ui.label("🎬 Video:");
                    let mut video_path =
                        self.state.media_folders.video_folder.display().to_string();
                    if ui.text_edit_singleline(&mut video_path).changed() {
                        self.state.media_folders.video_folder = PathBuf::from(video_path);
                    }
                    if ui.button("📂").clone().on_hover_text("Browse").clicked() {
                        // Would trigger folder dialog
                    }
                });

                ui.horizontal(|ui| {
                    ui.label("🖼 Image:");
                    let mut image_path =
                        self.state.media_folders.image_folder.display().to_string();
                    if ui.text_edit_singleline(&mut image_path).changed() {
                        self.state.media_folders.image_folder = PathBuf::from(image_path);
                    }
                    if ui.button("📂").clone().on_hover_text("Browse").clicked() {
                        // Would trigger folder dialog
                    }
                });

                ui.horizontal(|ui| {
                    ui.label("🎵 Audio:");
                    let mut audio_path =
                        self.state.media_folders.audio_folder.display().to_string();
                    if ui.text_edit_singleline(&mut audio_path).changed() {
                        self.state.media_folders.audio_folder = PathBuf::from(audio_path);
                    }
                    if ui.button("📂").clone().on_hover_text("Browse").clicked() {
                        // Would trigger folder dialog
                    }
                });

                ui.horizontal(|ui| {
                    if ui.button("Apply Video Folder").clicked() {
                        let path = self.state.media_folders.video_folder.clone();
                        super::history::navigate_to(&mut self.state, path);
                    }
                    if ui.button("Apply Image Folder").clicked() {
                        let path = self.state.media_folders.image_folder.clone();
                        super::history::navigate_to(&mut self.state, path);
                    }
                    if ui.button("Apply Audio Folder").clicked() {
                        let path = self.state.media_folders.audio_folder.clone();
                        super::history::navigate_to(&mut self.state, path);
                    }
                });
            });
        }

        ui.separator();

        // Search and filter bar - wrapped in horizontal scroll to prevent forcing sidebar width
        egui::ScrollArea::horizontal().id_salt("media_filter_scroll").show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label("🔍");
                let search_response = ui.text_edit_singleline(&mut self.state.search_query);
                if search_response.changed() {
                    self.state.search_query_lower = if self.state.search_query.is_empty() {
                        None
                    } else {
                        Some(self.state.search_query.to_lowercase())
                    };
                }

                ui.separator();

                ui.label(locale.t("media-browser-filter"));
                ui.selectable_value(
                    &mut self.state.filter_type,
                    None,
                    locale.t("media-browser-all"),
                );
                ui.selectable_value(
                    &mut self.state.filter_type,
                    Some(MediaType::Video),
                    locale.t("media-browser-video"),
                );
                ui.selectable_value(
                    &mut self.state.filter_type,
                    Some(MediaType::Image),
                    locale.t("media-browser-image"),
                );
                ui.selectable_value(
                    &mut self.state.filter_type,
                    Some(MediaType::Audio),
                    locale.t("media-browser-audio"),
                );

                ui.separator();

                // View mode
                ui.selectable_value(
                    &mut self.state.view_mode,
                    ViewMode::Grid,
                    locale.t("media-browser-view-grid"),
                );
                ui.selectable_value(
                    &mut self.state.view_mode,
                    ViewMode::List,
                    locale.t("media-browser-view-list"),
                );

                ui.separator();

                // Sort mode
                egui::ComboBox::from_label(locale.t("media-browser-sort"))
                    .selected_text(format!("{:?}", self.state.sort_mode))
                    .show_ui(ui, |ui| {
                        ui.selectable_value(
                            &mut self.state.sort_mode,
                            SortMode::Name,
                            locale.t("media-browser-sort-name"),
                        );
                        ui.selectable_value(
                            &mut self.state.sort_mode,
                            SortMode::Type,
                            locale.t("media-browser-sort-type"),
                        );
                        ui.selectable_value(
                            &mut self.state.sort_mode,
                            SortMode::Size,
                            locale.t("media-browser-sort-size"),
                        );
                    });
            });
        });

        ui.separator();

        // Content area
        egui::ScrollArea::vertical().show(ui, |ui| {
            if self.state.scan_tasks_active.load(std::sync::atomic::Ordering::SeqCst) > 0 {
                ui.vertical_centered(|ui| {
                    ui.add_space(40.0);
                    ui.spinner();
                    ui.label(locale.t("media-browser-loading"));
                });
                return;
            }

            // Collect indices to avoid borrowing issues
            let entry_indices: Vec<usize> =
                self.state.filtered_entries().into_iter().map(|(i, _)| i).collect();

            if entry_indices.is_empty() {
                ui.vertical_centered(|ui| {
                    ui.add_space(40.0);
                    // Differentiate between empty folder and no search results
                    if self.state.entries.is_empty() {
                        ui.label(locale.t("media-browser-empty-folder"));
                    } else {
                        ui.label(locale.t("media-browser-no-results"));
                    }
                });
            } else {
                match self.state.view_mode {
                    ViewMode::Grid => {
                        action = self.render_grid_view(ui, &entry_indices, icons);
                    }
                    ViewMode::List => {
                        action = self.render_list_view(ui, &entry_indices, icons);
                    }
                }
            }
        });

        action
    }

    /// Render grid view
    fn render_grid_view(
        &mut self,
        ui: &mut Ui,
        entry_indices: &[usize],
        _icons: Option<&IconManager>,
    ) -> Option<MediaBrowserAction> {
        let mut action = None;
        let item_size = Vec2::new(self.state.thumbnail_size, self.state.thumbnail_size + 40.0);
        let available_width = ui.available_width();
        let columns = (available_width / (item_size.x + 8.0)).floor().max(1.0) as usize;

        egui::Grid::new("media_grid").spacing([8.0, 8.0]).min_col_width(item_size.x).show(
            ui,
            |ui| {
                for (i, &idx) in entry_indices.iter().enumerate() {
                    if i > 0 && i % columns == 0 {
                        ui.end_row();
                    }

                    let entry = &self.state.entries[idx];
                    let response = self.render_thumbnail_item(ui, entry, idx, _icons);

                    if response.clicked() {
                        self.state.selected = Some(idx);
                        action = Some(MediaBrowserAction::FileSelected(entry.path.clone()));
                    }

                    if response.double_clicked() {
                        action = Some(MediaBrowserAction::FileDoubleClicked(entry.path.clone()));
                    }

                    if response.hovered() && self.state.hovered != Some(idx) {
                        self.state.hovered = Some(idx);
                        self.state.hover_start = Some(Instant::now());
                    }
                }
            },
        );

        // Check for preview trigger
        if let Some(hover_time) = self.state.hover_start {
            if hover_time.elapsed().as_secs_f32() > self.state.preview_delay {
                if let Some(hovered_idx) = self.state.hovered {
                    if hovered_idx < self.state.entries.len() {
                        let entry = &self.state.entries[hovered_idx];
                        action = Some(MediaBrowserAction::StartPreview(entry.path.clone()));
                    }
                }
            }
        }

        action
    }

    /// Render list view
    fn render_list_view(
        &mut self,
        ui: &mut Ui,
        entry_indices: &[usize],
        icons: Option<&IconManager>,
    ) -> Option<MediaBrowserAction> {
        let mut action = None;

        for &idx in entry_indices {
            let entry = &self.state.entries[idx];
            ui.horizontal(|ui| {
                // Icon
                if let Some(mgr) = icons {
                    if let Some(icon) = entry.file_type.app_icon() {
                        if let Some(img) = mgr.image(icon, 16.0) {
                            ui.add(img);
                        } else {
                            ui.label(entry.file_type.icon());
                        }
                    } else {
                        ui.label(entry.file_type.icon());
                    }
                } else {
                    ui.label(entry.file_type.icon());
                }

                // Color tag
                if let Some(color) = entry.color_tag {
                    ui.colored_label(color, "●");
                }

                // Name (clickable)
                let name_label = ui.selectable_label(self.state.selected == Some(idx), &entry.name);
                if name_label.clicked() {
                    self.state.selected = Some(idx);
                    action = Some(MediaBrowserAction::FileSelected(entry.path.clone()));
                }
                if name_label.double_clicked() {
                    action = Some(MediaBrowserAction::FileDoubleClicked(entry.path.clone()));
                }

                // Size
                ui.label(format_size(entry.size_bytes));

                // Duration
                if let Some(duration) = entry.duration_secs {
                    ui.label(format_duration(duration));
                }
            });
        }

        action
    }

    /// Render a thumbnail item
    fn render_thumbnail_item(
        &self,
        ui: &mut Ui,
        entry: &MediaEntry,
        idx: usize,
        icons: Option<&IconManager>,
    ) -> Response {
        let size = Vec2::new(self.state.thumbnail_size, self.state.thumbnail_size + 40.0);
        let (rect, response) = ui.allocate_exact_size(size, Sense::click());

        if ui.is_rect_visible(rect) {
            let visuals = ui.style().interact(&response);

            // Background
            let bg_color = if self.state.selected == Some(idx) {
                ui.visuals().selection.bg_fill
            } else if response.hovered() {
                ui.visuals().widgets.hovered.bg_fill
            } else {
                ui.visuals().widgets.inactive.bg_fill
            };

            ui.painter().rect_filled(rect, 2.0, bg_color);

            // Thumbnail area
            let thumb_rect = egui::Rect::from_min_size(
                rect.min,
                Vec2::new(self.state.thumbnail_size, self.state.thumbnail_size),
            );

            if let Some(thumbnail) = &entry.thumbnail {
                // Render thumbnail texture
                ui.painter().image(
                    thumbnail.texture_handle.id(),
                    thumb_rect,
                    egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)),
                    Color32::WHITE,
                );
            } else {
                // Placeholder
                ui.painter().rect_filled(thumb_rect, 2.0, ui.visuals().extreme_bg_color);

                // Try to render icon, fallback to emoji
                let mut rendered_icon = false;
                if let Some(mgr) = icons {
                    if let Some(app_icon) = entry.file_type.app_icon() {
                        if let Some(texture) = mgr.get(app_icon) {
                            // Calculate icon size (centered, 64x64 or smaller)
                            let icon_size = Vec2::new(64.0, 64.0).min(thumb_rect.size() * 0.8);
                            let icon_rect =
                                egui::Rect::from_center_size(thumb_rect.center(), icon_size);

                            ui.painter().image(
                                texture.id(),
                                icon_rect,
                                egui::Rect::from_min_max(
                                    egui::pos2(0.0, 0.0),
                                    egui::pos2(1.0, 1.0),
                                ),
                                ui.visuals().text_color().gamma_multiply(0.8), // Tinted slightly
                            );
                            rendered_icon = true;
                        }
                    }
                }

                if !rendered_icon {
                    let icon_pos = thumb_rect.center() - Vec2::new(20.0, 20.0);
                    ui.painter().text(
                        icon_pos,
                        egui::Align2::LEFT_TOP,
                        entry.file_type.icon(),
                        egui::FontId::proportional(40.0),
                        ui.visuals().text_color().gamma_multiply(0.4),
                    );
                }
            }

            // Color tag indicator
            if let Some(color) = entry.color_tag {
                let tag_rect = egui::Rect::from_min_size(
                    thumb_rect.min + Vec2::new(4.0, 4.0),
                    Vec2::new(12.0, 12.0),
                );
                ui.painter().circle_filled(tag_rect.center(), 6.0, color);
            }

            // Name label
            let name_rect = egui::Rect::from_min_size(
                rect.min + Vec2::new(0.0, self.state.thumbnail_size),
                Vec2::new(self.state.thumbnail_size, 40.0),
            );
            ui.painter().text(
                name_rect.center_top() + Vec2::new(0.0, 4.0),
                egui::Align2::CENTER_TOP,
                &entry.name,
                egui::FontId::proportional(12.0),
                visuals.text_color(),
            );
        }

        response
    }
}

/// Format file size for display
fn format_size(bytes: u64) -> String {
    const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
    let mut size = bytes as f64;
    let mut unit_idx = 0;

    while size >= 1024.0 && unit_idx < UNITS.len() - 1 {
        size /= 1024.0;
        unit_idx += 1;
    }

    format!("{:.1} {}", size, UNITS[unit_idx])
}

/// Format duration for display
fn format_duration(seconds: f32) -> String {
    let minutes = (seconds / 60.0).floor() as u32;
    let secs = (seconds % 60.0).floor() as u32;
    format!("{:02}:{:02}", minutes, secs)
}

impl MediaBrowser {
    pub fn navigate_back(&mut self) {
        super::history::navigate_back(&mut self.state);
    }

    pub fn navigate_forward(&mut self) {
        super::history::navigate_forward(&mut self.state);
    }

    pub fn navigate_up(&mut self) {
        super::history::navigate_up(&mut self.state);
    }

    pub fn process_scans(&mut self) {
        super::scan::process_scans(&mut self.state);
    }
}
