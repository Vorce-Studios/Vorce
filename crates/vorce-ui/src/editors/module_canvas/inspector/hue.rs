use egui::Ui;
use vorce_core::module::HueNodeType;

pub fn render_hue_ui(ui: &mut Ui, hue_node: &mut HueNodeType) {
    ui.label("Philips Hue Target");
    ui.separator();

    match hue_node {
        HueNodeType::SingleLamp {
            id,
            name,
            brightness,
            color,
            effect: _,
            effect_active,
        } => {
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
            // effect ...
            ui.checkbox(effect_active, "Effect Active");
        }
        HueNodeType::MultiLamp {
            ids,
            name,
            brightness,
            color,
            effect: _,
            effect_active,
        } => {
            ui.horizontal(|ui| {
                ui.label("Group Name:");
                ui.text_edit_singleline(name);
            });
            ui.label("Lamp IDs (comma separated):");
            let mut ids_str = ids.join(", ");
            if ui.text_edit_singleline(&mut ids_str).changed() {
                *ids = ids_str
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
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
            ui.checkbox(effect_active, "Effect Active");
        }
        HueNodeType::EntertainmentGroup {
            name,
            brightness,
            color,
            effect: _,
            effect_active,
        } => {
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
            ui.checkbox(effect_active, "Effect Active");
        }
    }
}
