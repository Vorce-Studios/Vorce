use super::SettingsContext;
use egui::{Context, RichText};
use vorce_ui::UIAction;

pub fn show(_ctx: &Context, ui: &mut egui::Ui, context: &mut SettingsContext) {
    ui.heading(
        RichText::new(format!(
            "{} & {}",
            context.ui_state.i18n.t("graphics"),
            context.ui_state.i18n.t("performance")
        ))
        .color(ui.visuals().strong_text_color()),
    );
    ui.add_space(4.0);
    egui::Grid::new("perf_grid").num_columns(2).spacing([20.0, 8.0]).show(ui, |ui| {
        ui.label(format!("{}:", context.ui_state.i18n.t("hw-accel")));
        ui.label("Enabled");
        ui.end_row();
        ui.label(format!("{}:", context.ui_state.i18n.t("target-fps")));
        let mut fps = context.ui_state.user_config.target_fps.unwrap_or(60.0);
        if ui.add(egui::Slider::new(&mut fps, 24.0..=144.0).suffix(" FPS")).changed() {
            context.ui_state.actions.push(UIAction::SetTargetFps(fps));
        }
        ui.end_row();
        ui.label("VSync Mode:");
        let vsync = context.ui_state.user_config.vsync_mode;
        egui::ComboBox::from_id_salt("vsync_select").selected_text(vsync.to_string()).show_ui(
            ui,
            |ui| {
                use vorce_ui::core::config::VSyncMode;
                for mode in [VSyncMode::Auto, VSyncMode::On, VSyncMode::Off] {
                    if ui.selectable_label(vsync == mode, mode.to_string()).clicked() {
                        context.ui_state.actions.push(UIAction::SetVsyncMode(mode));
                    }
                }
            },
        );
        ui.end_row();
        ui.label("Preferred GPU:");
        let current_gpu = context.ui_state.user_config.preferred_gpu.clone();
        let gpu_text = current_gpu.unwrap_or_else(|| "Default".to_string());
        ui.horizontal(|ui| {
            let mut temp_gpu = gpu_text.clone();
            if ui.text_edit_singleline(&mut temp_gpu).changed() {
                let new_val = if temp_gpu.trim().is_empty()
                    || temp_gpu.trim().eq_ignore_ascii_case("default")
                {
                    None
                } else {
                    Some(temp_gpu.trim().to_string())
                };
                context.ui_state.actions.push(UIAction::SetPreferredGpu(new_val));
            }
            if ui.button("Clear").clicked() {
                context.ui_state.actions.push(UIAction::SetPreferredGpu(None));
            }
        });
        ui.end_row();
    });
    ui.add_space(10.0);
    ui.separator();
}
