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
pub(crate) fn render_video_multi_ui(
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
        _ => {}
    }
}
