use super::super::capabilities;
use egui::Ui;
use vorce_core::module::SourceType;

pub fn render_shader_ui(ui: &mut Ui, source: &mut SourceType) {
    if let SourceType::Shader { name, params: _ } = source {
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
}
