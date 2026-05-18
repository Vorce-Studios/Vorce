use crate::i18n::LocaleManager;
use crate::icons::IconManager;
use egui::{Color32, Response, Sense, Ui, Vec2};
use std::path::PathBuf;
use std::time::Instant;

use super::state::MediaBrowser;
use super::types::{MediaBrowserAction, MediaEntry, MediaType, SortMode, ViewMode};
use super::utils::{format_duration, format_size};

pub fn render_ui(
    browser: &mut MediaBrowser,
    ui: &mut Ui,
    locale: &LocaleManager,
    icons: Option<&IconManager>,
) -> Option<MediaBrowserAction> {
    browser.process_thumbnails(ui.ctx());
    browser.process_metadata(ui.ctx());
    browser.process_scans();

    let mut action = None;

    ui.horizontal(|ui| {
        ui.add_enabled_ui(browser.history_index > 0, |ui| {
            if ui.button("◀").clone().on_hover_text(locale.t("media-browser-back")).clicked() {
                browser.navigate_back();
            }
        });

        ui.add_enabled_ui(browser.history_index < browser.history.len() - 1, |ui| {
            if ui.button("▶").clone().on_hover_text(locale.t("media-browser-forward")).clicked() {
                browser.navigate_forward();
            }
        });

        if ui.button("⬆").clone().on_hover_text(locale.t("media-browser-up")).clicked() {
            browser.navigate_up();
        }

        if ui.button("🔄").clone().on_hover_text(locale.t("media-browser-refresh")).clicked() {
            browser.refresh();
        }

        if ui.button("⚙").clone().on_hover_text("Folder Settings").clicked() {
            browser.show_folder_settings = !browser.show_folder_settings;
        }

        ui.separator();

        let path_response = ui.add(
            egui::TextEdit::singleline(&mut browser.path_input)
                .desired_width(ui.available_width() - 30.0)
                .hint_text("Enter path..."),
        );

        if path_response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
            let new_path = PathBuf::from(&browser.path_input);
            if new_path.is_dir() {
                browser.navigate_to(new_path);
            }
        }
    });

    if browser.show_folder_settings {
        ui.group(|ui| {
            ui.label("📁 Media Folder Settings");
            ui.separator();

            ui.horizontal(|ui| {
                ui.label("🎬 Video:");
                let mut video_path = browser.media_folders.video_folder.display().to_string();
                if ui.text_edit_singleline(&mut video_path).changed() {
                    browser.media_folders.video_folder = PathBuf::from(video_path);
                }
            });

            ui.horizontal(|ui| {
                ui.label("🖼 Image:");
                let mut image_path = browser.media_folders.image_folder.display().to_string();
                if ui.text_edit_singleline(&mut image_path).changed() {
                    browser.media_folders.image_folder = PathBuf::from(image_path);
                }
            });

            ui.horizontal(|ui| {
                ui.label("🎵 Audio:");
                let mut audio_path = browser.media_folders.audio_folder.display().to_string();
                if ui.text_edit_singleline(&mut audio_path).changed() {
                    browser.media_folders.audio_folder = PathBuf::from(audio_path);
                }
            });

            ui.horizontal(|ui| {
                if ui.button("Apply Video Folder").clicked() {
                    let path = browser.media_folders.video_folder.clone();
                    browser.navigate_to(path);
                }
                if ui.button("Apply Image Folder").clicked() {
                    let path = browser.media_folders.image_folder.clone();
                    browser.navigate_to(path);
                }
                if ui.button("Apply Audio Folder").clicked() {
                    let path = browser.media_folders.audio_folder.clone();
                    browser.navigate_to(path);
                }
            });
        });
    }

    ui.separator();

    egui::ScrollArea::horizontal().id_salt("media_filter_scroll").show(ui, |ui| {
        ui.horizontal(|ui| {
            ui.label("🔍");
            let search_response = ui.text_edit_singleline(&mut browser.search_query);
            if search_response.changed() {
                browser.search_query_lower = if browser.search_query.is_empty() {
                    None
                } else {
                    Some(browser.search_query.to_lowercase())
                };
            }

            ui.separator();

            ui.label(locale.t("media-browser-filter"));
            ui.selectable_value(&mut browser.filter_type, None, locale.t("media-browser-all"));
            ui.selectable_value(
                &mut browser.filter_type,
                Some(MediaType::Video),
                locale.t("media-browser-video"),
            );
            ui.selectable_value(
                &mut browser.filter_type,
                Some(MediaType::Image),
                locale.t("media-browser-image"),
            );
            ui.selectable_value(
                &mut browser.filter_type,
                Some(MediaType::Audio),
                locale.t("media-browser-audio"),
            );

            ui.separator();

            ui.selectable_value(
                &mut browser.view_mode,
                ViewMode::Grid,
                locale.t("media-browser-view-grid"),
            );
            ui.selectable_value(
                &mut browser.view_mode,
                ViewMode::List,
                locale.t("media-browser-view-list"),
            );

            ui.separator();

            egui::ComboBox::from_label(locale.t("media-browser-sort"))
                .selected_text(format!("{:?}", browser.sort_mode))
                .show_ui(ui, |ui| {
                    ui.selectable_value(
                        &mut browser.sort_mode,
                        SortMode::Name,
                        locale.t("media-browser-sort-name"),
                    );
                    ui.selectable_value(
                        &mut browser.sort_mode,
                        SortMode::Type,
                        locale.t("media-browser-sort-type"),
                    );
                    ui.selectable_value(
                        &mut browser.sort_mode,
                        SortMode::Size,
                        locale.t("media-browser-sort-size"),
                    );
                });
        });
    });

    ui.separator();

    egui::ScrollArea::vertical().show(ui, |ui| {
        if browser.scan_tasks_active.load(std::sync::atomic::Ordering::SeqCst) > 0 {
            ui.vertical_centered(|ui| {
                ui.add_space(40.0);
                ui.spinner();
                ui.label(locale.t("media-browser-loading"));
            });
            return;
        }

        let entry_indices: Vec<usize> = browser.filtered_entries().into_iter().map(|(i, _)| i).collect();

        if entry_indices.is_empty() {
            ui.vertical_centered(|ui| {
                ui.add_space(40.0);
                if browser.entries.is_empty() {
                    ui.label(locale.t("media-browser-empty-folder"));
                } else {
                    ui.label(locale.t("media-browser-no-results"));
                }
            });
        } else {
            match browser.view_mode {
                ViewMode::Grid => {
                    action = render_grid_view(browser, ui, &entry_indices, icons);
                }
                ViewMode::List => {
                    action = render_list_view(browser, ui, &entry_indices, icons);
                }
            }
        }
    });

    action
}

fn render_grid_view(
    browser: &mut MediaBrowser,
    ui: &mut Ui,
    entry_indices: &[usize],
    icons: Option<&IconManager>,
) -> Option<MediaBrowserAction> {
    let mut action = None;
    let item_size = Vec2::new(browser.thumbnail_size, browser.thumbnail_size + 40.0);
    let available_width = ui.available_width();
    let columns = (available_width / (item_size.x + 8.0)).floor().max(1.0) as usize;

    egui::Grid::new("media_grid").spacing([8.0, 8.0]).min_col_width(item_size.x).show(
        ui,
        |ui| {
            for (i, &idx) in entry_indices.iter().enumerate() {
                if i > 0 && i % columns == 0 {
                    ui.end_row();
                }

                let entry = &browser.entries[idx];
                let response = render_thumbnail_item(browser, ui, entry, idx, icons);

                if response.clicked() {
                    browser.selected = Some(idx);
                    action = Some(MediaBrowserAction::FileSelected(entry.path.clone()));
                }

                if response.double_clicked() {
                    action = Some(MediaBrowserAction::FileDoubleClicked(entry.path.clone()));
                }

                if response.hovered() && browser.hovered != Some(idx) {
                    browser.hovered = Some(idx);
                    browser.hover_start = Some(Instant::now());
                }
            }
        },
    );

    if let Some(hover_time) = browser.hover_start {
        if hover_time.elapsed().as_secs_f32() > browser.preview_delay {
            if let Some(hovered_idx) = browser.hovered {
                if hovered_idx < browser.entries.len() {
                    let entry = &browser.entries[hovered_idx];
                    action = Some(MediaBrowserAction::StartPreview(entry.path.clone()));
                }
            }
        }
    }

    action
}

fn render_list_view(
    browser: &mut MediaBrowser,
    ui: &mut Ui,
    entry_indices: &[usize],
    icons: Option<&IconManager>,
) -> Option<MediaBrowserAction> {
    let mut action = None;

    for &idx in entry_indices {
        let entry = &browser.entries[idx];
        ui.horizontal(|ui| {
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

            if let Some(color) = entry.color_tag {
                ui.colored_label(color, "●");
            }

            let name_label = ui.selectable_label(browser.selected == Some(idx), &entry.name);
            if name_label.clicked() {
                browser.selected = Some(idx);
                action = Some(MediaBrowserAction::FileSelected(entry.path.clone()));
            }
            if name_label.double_clicked() {
                action = Some(MediaBrowserAction::FileDoubleClicked(entry.path.clone()));
            }

            ui.label(format_size(entry.size_bytes));

            if let Some(duration) = entry.duration_secs {
                ui.label(format_duration(duration));
            }
        });
    }

    action
}

fn render_thumbnail_item(
    browser: &MediaBrowser,
    ui: &mut Ui,
    entry: &MediaEntry,
    idx: usize,
    icons: Option<&IconManager>,
) -> Response {
    let size = Vec2::new(browser.thumbnail_size, browser.thumbnail_size + 40.0);
    let (rect, response) = ui.allocate_exact_size(size, Sense::click());

    if ui.is_rect_visible(rect) {
        let visuals = ui.style().interact(&response);

        let bg_color = if browser.selected == Some(idx) {
            ui.visuals().selection.bg_fill
        } else if response.hovered() {
            ui.visuals().widgets.hovered.bg_fill
        } else {
            ui.visuals().widgets.inactive.bg_fill
        };

        ui.painter().rect_filled(rect, 2.0, bg_color);

        let thumb_rect = egui::Rect::from_min_size(
            rect.min,
            Vec2::new(browser.thumbnail_size, browser.thumbnail_size),
        );

        if let Some(thumbnail) = &entry.thumbnail {
            ui.painter().image(
                thumbnail.texture_handle.id(),
                thumb_rect,
                egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)),
                Color32::WHITE,
            );
        } else {
            ui.painter().rect_filled(thumb_rect, 2.0, ui.visuals().extreme_bg_color);

            let mut rendered_icon = false;
            if let Some(mgr) = icons {
                if let Some(app_icon) = entry.file_type.app_icon() {
                    if let Some(texture) = mgr.get(app_icon) {
                        let icon_size = Vec2::new(64.0, 64.0).min(thumb_rect.size() * 0.8);
                        let icon_rect = egui::Rect::from_center_size(thumb_rect.center(), icon_size);

                        ui.painter().image(
                            texture.id(),
                            icon_rect,
                            egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)),
                            ui.visuals().text_color().gamma_multiply(0.8),
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

        if let Some(color) = entry.color_tag {
            let tag_rect = egui::Rect::from_min_size(
                thumb_rect.min + Vec2::new(4.0, 4.0),
                Vec2::new(12.0, 12.0),
            );
            ui.painter().circle_filled(tag_rect.center(), 6.0, color);
        }

        let name_rect = egui::Rect::from_min_size(
            rect.min + Vec2::new(0.0, browser.thumbnail_size),
            Vec2::new(browser.thumbnail_size, 40.0),
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
