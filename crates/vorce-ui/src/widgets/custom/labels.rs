use crate::theme::colors;
use egui::{CornerRadius, Pos2, Rect, Sense, Ui, Vec2};

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

#[cfg(test)]
mod tests {
    use super::*;
    use egui::{Context, Ui};

    fn test_ui(func: impl FnMut(&mut Ui)) {
        let ctx = Context::default();
        let mut func = func;
        #[allow(deprecated)]
        let _ = ctx.run(Default::default(), |ctx| {
            #[allow(deprecated)]
            egui::CentralPanel::default().show(ctx, |ui| {
                func(ui);
            });
        });
    }

    #[test]
    fn test_render_header() {
        test_ui(|ui| {
            render_header(ui, "Test Header");
        });
    }

    #[test]
    fn test_render_info_label() {
        test_ui(|ui| {
            render_info_label(ui, "Test Label");
        });
    }

    #[test]
    fn test_render_info_label_with_size() {
        test_ui(|ui| {
            render_info_label_with_size(ui, "Test Label", 12.0);
        });
    }

    #[test]
    fn test_render_missing_preview_banner() {
        test_ui(|ui| {
            render_missing_preview_banner(ui);
        });
    }
}
