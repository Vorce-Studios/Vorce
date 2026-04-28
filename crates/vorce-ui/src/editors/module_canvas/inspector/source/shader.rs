use super::super::capabilities;
// Extracted shader module
use super::super::super::state::ModuleCanvas;
use crate::UIAction;
use egui::Ui;
use vorce_core::module::{ModuleId, ModulePartId, SourceType};
pub fn render_shader_source(
    _canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    source: &mut SourceType,
    _part_id: ModulePartId,
    _module_id: ModuleId,
    _shared_media_ids: &[String],
    _actions: &mut Vec<UIAction>,
) {
    #[allow(clippy::single_match)]
    match source {
        SourceType::Shader { name, params: _ } => {
            ui.label("\u{1F3A8} Shader");
            let supported = capabilities::is_source_type_enum_supported(true, false, false, false);
            if !supported {
                capabilities::render_unsupported_warning(
                    ui,
                    "Shader nodes are not fully supported in the current render pipeline.",
                );
            }
            ui.add_enabled_ui(supported, |ui| {
                egui::Grid::new("shader_grid").num_columns(2).spacing([10.0, 8.0]).show(ui, |ui| {
                    ui.label("Name:");
                    ui.text_edit_singleline(name);
                    ui.end_row();
                });
            });
        }
        _ => {}
    }
}
