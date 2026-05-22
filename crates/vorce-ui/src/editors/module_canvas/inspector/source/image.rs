use crate::theme::colors;
use crate::widgets::styled_slider;
use crate::UIAction;
use egui::{Ui, Vec2};
use vorce_core::module::{BevyCameraMode, ModuleId, ModulePartId, SourceType};

use super::super::super::state::ModuleCanvas;
use super::super::super::types::MediaPlaybackCommand;
use super::super::capabilities;
use super::super::common::{
    render_common_controls, render_info_label, render_timeline, render_transport_controls,
};

#![allow(clippy::ptr_arg)]
#[allow(clippy::too_many_arguments)]
#[allow(unused_variables)]
#[allow(unused_imports)]
pub(crate) fn render_image_ui(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    source: &mut SourceType,
    part_id: ModulePartId,
    module_id: ModuleId,
    shared_media_ids: &[String],
    actions: &mut Vec<UIAction>,
) {
    match source {
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
        _ => {}
    }
}
