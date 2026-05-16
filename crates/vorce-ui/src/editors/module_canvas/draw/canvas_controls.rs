use super::super::state::ModuleCanvas;
use egui::Ui;

pub fn draw_empty_canvas(ui: &mut Ui) {
    ui.centered_and_justified(|ui| {
        ui.vertical_centered(|ui| {
            ui.add_space(50.0);
            ui.heading("\u{1F527} Module Canvas");
            ui.add_space(10.0);
            ui.label("Click '\u{2795} New Module' to create a module.");
            ui.label("Please select an existing module from the toolbar above.");
        });
    });
}

pub fn draw_zoom_controls(canvas: &mut ModuleCanvas, ui: &mut Ui) {
    egui::Area::new(egui::Id::new("canvas_zoom_area"))
        .anchor(egui::Align2::RIGHT_BOTTOM, egui::vec2(-20.0, -20.0))
        .show(ui.ctx(), |ui| {
            crate::widgets::panel::cyber_panel_frame(ui.style()).show(
                ui,
                |ui: &mut egui::Ui| {
                    ui.horizontal(|ui: &mut egui::Ui| {
                        ui.spacing_mut().item_spacing.x = 4.0;
                        if ui
                            .button(egui::RichText::new("-").strong())
                            .on_hover_text("Zoom Out")
                            .clicked()
                        {
                            canvas.zoom = (canvas.zoom / 1.2).max(0.1);
                        }

                        ui.add(
                            egui::Slider::new(&mut canvas.zoom, 0.1..=2.0)
                                .show_value(false)
                                .trailing_fill(true),
                        );

                        if ui
                            .button(egui::RichText::new("+").strong())
                            .on_hover_text("Zoom In")
                            .clicked()
                        {
                            canvas.zoom = (canvas.zoom * 1.2).min(2.0);
                        }
                        ui.label(
                            egui::RichText::new(format!("{:.0}%", canvas.zoom * 100.0))
                                .size(11.0)
                                .color(ui.visuals().text_color()),
                        );
                    });
                },
            );
        });
}

pub fn draw_connection_context_menu(ui: &mut Ui, inner_rect: egui::Rect) -> bool {
    let mut delete_clicked = false;
    ui.scope_builder(egui::UiBuilder::new().max_rect(inner_rect), |ui| {
        ui.vertical(|ui| {
            if crate::widgets::custom::hold_to_action_button(
                ui,
                "\u{1F5D1} Delete Connection",
                crate::theme::colors::ERROR_COLOR,
                "Delete Connection",
            ) {
                delete_clicked = true;
            }
        });
    });
    delete_clicked
}
