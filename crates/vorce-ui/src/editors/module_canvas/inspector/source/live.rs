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
pub(crate) fn render_live_ui(
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
        SourceType::LiveInput { device_id } => {
            ui.label("\u{1F4F9} Live Input");
            let supported = capabilities::is_source_type_enum_supported(false, true, false, false);
            if !supported {
                capabilities::render_unsupported_warning(
                    ui,
                    "Live Input is currently not fully wired up to the runtime.",
                );
            }
            ui.add_enabled_ui(supported, |ui| {
                egui::Grid::new("live_input_grid").num_columns(2).spacing([10.0, 8.0]).show(
                    ui,
                    |ui| {
                        ui.label("Device ID:");
                        ui.add(egui::Slider::new(device_id, 0..=10));
                        ui.end_row();
                    },
                );
            });
        }
        _ => {}
    }
}
