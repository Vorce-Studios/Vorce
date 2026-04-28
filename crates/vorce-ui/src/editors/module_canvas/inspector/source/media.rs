// Extracted media module
use super::super::super::state::ModuleCanvas;
use super::super::super::types::MediaPlaybackCommand;
use super::super::common::{
    render_common_controls, render_info_label, render_timeline, render_transport_controls,
};
use crate::theme::colors;
use crate::widgets::styled_slider;
use crate::UIAction;
use egui::{Ui, Vec2};
use vorce_core::module::{ModuleId, ModulePartId, SourceType};
pub fn render_media_source(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    source: &mut SourceType,
    part_id: ModulePartId,
    module_id: ModuleId,
    shared_media_ids: &[String],
    actions: &mut Vec<UIAction>,
) {
    match source {
        SourceType::MediaFile {
            path,
            speed,
            loop_enabled,
            start_time,
            end_time,
            opacity,
            blend_mode,
            brightness,
            contrast,
            saturation,
            hue_shift,
            scale_x,
            scale_y,
            rotation,
            offset_x,
            offset_y,
            flip_horizontal,
            flip_vertical,
            reverse_playback,
            target_width,
            target_height,
            target_fps,
            ..
        }
        | SourceType::VideoUni {
            path,
            speed,
            loop_enabled,
            start_time,
            end_time,
            opacity,
            blend_mode,
            brightness,
            contrast,
            saturation,
            hue_shift,
            scale_x,
            scale_y,
            rotation,
            offset_x,
            offset_y,
            flip_horizontal,
            flip_vertical,
            reverse_playback,
            target_width,
            target_height,
            target_fps,
            ..
        } => {
            // Media Picker (common for file-based video)
            if path.is_empty() {
                ui.horizontal(|ui| {
                    if ui.button("Select...").clicked() {
                        actions.push(UIAction::PickMediaFile(module_id, part_id, "".to_string()));
                    }
                    render_info_label(ui, "No media loaded");
                });
            } else {
                ui.collapsing("📁 File Info", |ui| {
                    ui.horizontal(|ui| {
                        ui.label("Path:");
                        ui.add(egui::TextEdit::singleline(path).desired_width(160.0));
                        if ui.button("\u{1F4C2}").on_hover_text("Select Media File").clicked() {
                            actions.push(UIAction::PickMediaFile(
                                module_id,
                                part_id,
                                "".to_string(),
                            ));
                        }
                    });
                });
            }

            // Playback Info
            let player_info = canvas.player_info.get(&part_id).cloned().unwrap_or_default();
            let video_duration = player_info.duration.max(1.0) as f32;
            let current_pos = player_info.current_time as f32;
            let is_playing = player_info.is_playing;

            // Timecode
            let current_min = (current_pos / 60.0) as u32;
            let current_sec = (current_pos % 60.0) as u32;
            let current_frac = ((current_pos * 100.0) % 100.0) as u32;
            let duration_min = (video_duration / 60.0) as u32;
            let duration_sec = (video_duration % 60.0) as u32;
            let duration_frac = ((video_duration * 100.0) % 100.0) as u32;

            ui.add_space(5.0);
            ui.vertical_centered(|ui| {
                ui.label(
                    egui::RichText::new(format!(
                        "{:02}:{:02}.{:02} / {:02}:{:02}.{:02}",
                        current_min,
                        current_sec,
                        current_frac,
                        duration_min,
                        duration_sec,
                        duration_frac
                    ))
                    .monospace()
                    .size(22.0)
                    .strong()
                    .color(if is_playing {
                        ui.visuals().strong_text_color()
                    } else {
                        ui.visuals().text_color()
                    }),
                );
            });
            ui.add_space(10.0);

            render_transport_controls(
                canvas,
                ui,
                part_id,
                is_playing,
                current_pos,
                *loop_enabled,
                *reverse_playback,
            );

            ui.add_space(10.0);

            // Preview
            if let Some(tex_id) = canvas.node_previews.get(&(module_id, part_id)) {
                let size = Vec2::new(ui.available_width(), ui.available_width() * 9.0 / 16.0);
                ui.image((*tex_id, size));
            }
            ui.add_space(4.0);

            render_timeline(canvas, ui, part_id, video_duration, current_pos, start_time, end_time);

            // Safe Reset Clip (Mary StyleUX)
            ui.vertical_centered(|ui| {
                ui.add_space(4.0);
                if crate::widgets::hold_to_action_button(
                    ui,
                    "\u{27F2} Reset Clip",
                    colors::WARN_COLOR,
                    "Reset Clip",
                ) {
                    *start_time = 0.0;
                    *end_time = 0.0;
                }
            });

            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.label("Playback Speed:");
                let speed_slider = styled_slider(ui, speed, 0.1..=4.0, 1.0);
                ui.label("x");
                if speed_slider.changed() {
                    actions.push(UIAction::MediaCommand(
                        part_id,
                        MediaPlaybackCommand::SetSpeed(*speed),
                    ));
                }
            });
            ui.separator();

            // === VIDEO OPTIONS ===
            ui.collapsing("\u{1F3AC} Video Options", |ui| {
                let mut reverse = *reverse_playback;
                if ui.checkbox(&mut reverse, "⏪ Reverse Playback").changed() {
                    actions.push(crate::UIAction::MediaCommand(
                        part_id,
                        MediaPlaybackCommand::SetReverse(reverse),
                    ));
                }

                ui.separator();
                ui.label("Seek Position:");
                // Note: Actual seek requires video duration from player
                // For now, just show the control - needs integration with player state
                ui.add_enabled_ui(video_duration > 0.0, |ui| {
                    let mut seek_pos: f64 = 0.0;
                    let seek_slider = ui.add(
                        egui::Slider::new(&mut seek_pos, 0.0..=100.0)
                            .text("Position")
                            .suffix("%")
                            .show_value(true),
                    );
                    if seek_slider.drag_stopped() && seek_slider.changed() {
                        // Convert percentage to duration-based seek
                        canvas.pending_playback_commands.push((
                            part_id,
                            MediaPlaybackCommand::Seek(
                                (seek_pos / 100.0) * f64::from(video_duration),
                            ),
                        ));
                    }
                });
            });
            ui.separator();

            ui.collapsing("📐 Target Overrides", |ui| {
                ui.horizontal(|ui| {
                    let mut w = target_width.unwrap_or(0);
                    let mut h = target_height.unwrap_or(0);
                    ui.label("Width:");
                    if ui.add(egui::DragValue::new(&mut w).speed(1)).changed() {
                        *target_width = if w > 0 { Some(w) } else { None };
                    }
                    ui.label("Height:");
                    if ui.add(egui::DragValue::new(&mut h).speed(1)).changed() {
                        *target_height = if h > 0 { Some(h) } else { None };
                    }
                });
                ui.horizontal(|ui| {
                    let mut fps = target_fps.unwrap_or(0.0);
                    ui.label("FPS:");
                    if ui.add(egui::DragValue::new(&mut fps).speed(1.0)).changed() {
                        *target_fps = if fps > 0.0 { Some(fps) } else { None };
                    }
                });
            });
            ui.separator();

            render_common_controls(
                ui,
                opacity,
                blend_mode,
                brightness,
                contrast,
                saturation,
                hue_shift,
                scale_x,
                scale_y,
                rotation,
                offset_x,
                offset_y,
                flip_horizontal,
                flip_vertical,
            );
        }
        SourceType::ImageUni {
            path,
            opacity,
            blend_mode,
            brightness,
            contrast,
            saturation,
            hue_shift,
            scale_x,
            scale_y,
            rotation,
            offset_x,
            offset_y,
            flip_horizontal,
            flip_vertical,
            target_width,
            target_height,
            ..
        } => {
            // Image Picker
            if path.is_empty() {
                ui.horizontal(|ui| {
                    if ui.button("Select...").clicked() {
                        actions.push(crate::UIAction::PickMediaFile(
                            module_id,
                            part_id,
                            "".to_string(),
                        ));
                    }
                    render_info_label(ui, "No image loaded");
                });
            } else {
                ui.collapsing("📁 File Info", |ui| {
                    ui.horizontal(|ui| {
                        ui.label("Path:");
                        ui.add(egui::TextEdit::singleline(path).desired_width(160.0));
                        if ui.button("\u{1F4C2}").on_hover_text("Select Image File").clicked() {
                            actions.push(crate::UIAction::PickMediaFile(
                                module_id,
                                part_id,
                                "".to_string(),
                            ));
                        }
                    });
                });
            }

            ui.separator();

            ui.collapsing("📐 Target Overrides", |ui| {
                ui.horizontal(|ui| {
                    let mut w = target_width.unwrap_or(0);
                    let mut h = target_height.unwrap_or(0);
                    ui.label("Width:");
                    if ui.add(egui::DragValue::new(&mut w).speed(1)).changed() {
                        *target_width = if w > 0 { Some(w) } else { None };
                    }
                    ui.label("Height:");
                    if ui.add(egui::DragValue::new(&mut h).speed(1)).changed() {
                        *target_height = if h > 0 { Some(h) } else { None };
                    }
                });
            });
            ui.separator();

            render_common_controls(
                ui,
                opacity,
                blend_mode,
                brightness,
                contrast,
                saturation,
                hue_shift,
                scale_x,
                scale_y,
                rotation,
                offset_x,
                offset_y,
                flip_horizontal,
                flip_vertical,
            );
        }
        SourceType::VideoMulti {
            shared_id,
            opacity,
            blend_mode,
            brightness,
            contrast,
            saturation,
            hue_shift,
            scale_x,
            scale_y,
            rotation,
            offset_x,
            offset_y,
            flip_horizontal,
            flip_vertical,
            ..
        } => {
            ui.label("\u{1F517} Shared Video Source");
            ui.horizontal(|ui| {
                ui.label("Shared ID:");
                ui.add(
                    egui::TextEdit::singleline(shared_id)
                        .hint_text("Enter ID...")
                        .desired_width(140.0),
                );

                egui::ComboBox::from_id_salt("shared_media_video")
                    .selected_text("Select Existing")
                    .show_ui(ui, |ui| {
                        for id in shared_media_ids {
                            if ui.selectable_label(shared_id == id, id).clicked() {
                                *shared_id = id.clone();
                            }
                        }
                    });
            });
            crate::widgets::custom::render_info_label_with_size(
                ui,
                "Use the same ID to sync multiple nodes.",
                10.0,
            );

            ui.separator();
            render_common_controls(
                ui,
                opacity,
                blend_mode,
                brightness,
                contrast,
                saturation,
                hue_shift,
                scale_x,
                scale_y,
                rotation,
                offset_x,
                offset_y,
                flip_horizontal,
                flip_vertical,
            );
        }
        SourceType::ImageMulti {
            shared_id,
            opacity,
            blend_mode,
            brightness,
            contrast,
            saturation,
            hue_shift,
            scale_x,
            scale_y,
            rotation,
            offset_x,
            offset_y,
            flip_horizontal,
            flip_vertical,
            ..
        } => {
            ui.label("\u{1F517} Shared Image Source");
            ui.horizontal(|ui| {
                ui.label("Shared ID:");
                ui.add(
                    egui::TextEdit::singleline(shared_id)
                        .hint_text("Enter ID...")
                        .desired_width(140.0),
                );

                egui::ComboBox::from_id_salt("shared_media_image")
                    .selected_text("Select Existing")
                    .show_ui(ui, |ui| {
                        for id in shared_media_ids {
                            if ui.selectable_label(shared_id == id, id).clicked() {
                                *shared_id = id.clone();
                            }
                        }
                    });
            });
            crate::widgets::custom::render_info_label_with_size(
                ui,
                "Use the same ID to sync multiple nodes.",
                10.0,
            );

            ui.separator();
            render_common_controls(
                ui,
                opacity,
                blend_mode,
                brightness,
                contrast,
                saturation,
                hue_shift,
                scale_x,
                scale_y,
                rotation,
                offset_x,
                offset_y,
                flip_horizontal,
                flip_vertical,
            );
        }
        _ => {}
    }
}
