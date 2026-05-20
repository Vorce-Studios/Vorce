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
#[cfg(target_os = "windows")]
#[allow(clippy::too_many_arguments)]
pub(crate) fn render_spout_ui(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    source: &mut SourceType,
    part_id: ModulePartId,
    module_id: ModuleId,
    shared_media_ids: &[String],
    actions: &mut Vec<UIAction>,
) {
    match source {
        #[cfg(target_os = "windows")]
        SourceType::SpoutInput { sender_name } => {
            ui.label("\u{1F6B0} Spout Input");
            let supported = capabilities::is_source_type_enum_supported(false, false, false, true);
            if !supported {
                capabilities::render_unsupported_warning(
                    ui,
                    "Spout Input is currently not fully wired up to the runtime.",
                );
            }
            ui.add_enabled_ui(supported, |ui| {
                ui.horizontal(|ui| {
                    ui.label("Sender:");
                    ui.text_edit_singleline(sender_name);
                });
            });
        _ => {}
    }
}
