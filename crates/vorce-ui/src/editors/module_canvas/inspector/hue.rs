use egui::Ui;
use vorce_core::module::HueNodeType;

pub fn render_hue_ui(ui: &mut Ui, hue_node: &mut HueNodeType) {
    match hue_node {
        HueNodeType::SingleLamp { id, name, brightness, color, effect, effect_active } => {
            ui.horizontal(|ui| {
                ui.label("Name:");
                ui.text_edit_singleline(name);
            });
            ui.horizontal(|ui| {
                ui.label("Lamp ID:");
                ui.text_edit_singleline(id);
            });
            ui.horizontal(|ui| {
                ui.label("Brightness:");
                ui.add(egui::Slider::new(brightness, 0.0..=1.0));
            });
            ui.horizontal(|ui| {
                ui.label("Color:");
                ui.color_edit_button_rgb(color);
            });
            ui.horizontal(|ui| {
                ui.label("Effect:");
                let effect_name = effect.get_or_insert_with(String::new);
                ui.text_edit_singleline(effect_name);
            });
            ui.checkbox(effect_active, "Effect Active");
        }
        HueNodeType::MultiLamp { ids, name, brightness, color, effect, effect_active } => {
            ui.horizontal(|ui| {
                ui.label("Group Name:");
                ui.text_edit_singleline(name);
            });
            ui.label("Lamp IDs (comma separated):");
            let mut ids_text = ids.join(", ");
            if ui.text_edit_singleline(&mut ids_text).changed() {
                *ids = ids_text
                    .split(',')
                    .map(str::trim)
                    .filter(|entry| !entry.is_empty())
                    .map(ToOwned::to_owned)
                    .collect();
            }
            ui.horizontal(|ui| {
                ui.label("Brightness:");
                ui.add(egui::Slider::new(brightness, 0.0..=1.0));
            });
            ui.horizontal(|ui| {
                ui.label("Color:");
                ui.color_edit_button_rgb(color);
            });
            ui.horizontal(|ui| {
                ui.label("Effect:");
                let effect_name = effect.get_or_insert_with(String::new);
                ui.text_edit_singleline(effect_name);
            });
            ui.checkbox(effect_active, "Effect Active");
        }
        HueNodeType::EntertainmentGroup { name, brightness, color, effect, effect_active } => {
            ui.horizontal(|ui| {
                ui.label("Area Name:");
                ui.text_edit_singleline(name);
            });
            ui.horizontal(|ui| {
                ui.label("Brightness:");
                ui.add(egui::Slider::new(brightness, 0.0..=1.0));
            });
            ui.horizontal(|ui| {
                ui.label("Color:");
                ui.color_edit_button_rgb(color);
            });
            ui.horizontal(|ui| {
                ui.label("Effect:");
                let effect_name = effect.get_or_insert_with(String::new);
                ui.text_edit_singleline(effect_name);
            });
            ui.checkbox(effect_active, "Effect Active");
        }
    }
}
