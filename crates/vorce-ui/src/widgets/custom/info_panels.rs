use super::hold_action::hold_to_action_button;
use crate::theme::colors;
use egui::{
    CornerRadius, Pos2, Rect, Sense, Ui, Vec2,
};

pub fn render_header(ui: &mut Ui, title: &str) {
    let desired_size = Vec2::new(ui.available_width(), 24.0);
    // Allocate space for the header
    let (rect, _response) = ui.allocate_at_least(desired_size, Sense::hover());

    let painter = ui.painter();
    // Header background
    painter.rect_filled(rect, CornerRadius::ZERO, colors::LIGHTER_GREY);

    let stripe_rect = Rect::from_min_size(rect.min, Vec2::new(2.0, rect.height()));
    painter.rect_filled(stripe_rect, CornerRadius::ZERO, colors::CYAN_ACCENT);

    let text_pos = Pos2::new(rect.min.x + 8.0, rect.center().y);
    painter.text(
        text_pos,
        egui::Align2::LEFT_CENTER,
        title,
        egui::FontId::proportional(14.0),
        ui.visuals().text_color(),
    );
}

/// Standardized informational text label for fallback/empty states.
pub fn render_info_label(ui: &mut Ui, text: &str) {
    ui.label(egui::RichText::new(text).weak().italics());
}

/// Standardized informational text label with customizable text size.
pub fn render_info_label_with_size(ui: &mut Ui, text: &str, size: f32) {
    ui.label(egui::RichText::new(text).size(size).weak().italics());
}

/// Standardized missing preview banner.
pub fn render_missing_preview_banner(ui: &mut Ui) {
    ui.group(|ui| {
        render_info_label(ui, "No preview available yet.");
    });
}

pub fn collapsing_header_with_reset(
    ui: &mut Ui,
    title: &str,
    default_open: bool,
    add_contents: impl FnOnce(&mut Ui),
) -> bool {
    let id = ui.make_persistent_id(title);
    let mut reset_clicked = false;
    egui::collapsing_header::CollapsingState::load_with_default_open(ui.ctx(), id, default_open)
        .show_header(ui, |ui| {
            ui.label(title);
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if hold_to_action_button(ui, "↺ Reset", colors::WARN_COLOR, "Reset") {
                    reset_clicked = true;
                }
            });
        })
        .body(|ui| {
            add_contents(ui);
        });
    reset_clicked
}
