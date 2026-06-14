use crate::theme::colors;
use egui::{
    Color32, Stroke, Ui,
};

/// A standard list item container for the Cyber Dark theme.
/// Handles selection, zebra striping, and layout consistency.
pub fn cyber_list_item<R>(
    ui: &mut Ui,
    id: egui::Id,
    selected: bool,
    alternate: bool,
    add_contents: impl FnOnce(&mut Ui) -> R,
) -> R {
    let bg_color = if selected {
        colors::CYAN_ACCENT.linear_multiply(0.2)
    } else if alternate {
        colors::DARKER_GREY // Subtle alternating background
    } else {
        Color32::TRANSPARENT
    };

    let stroke = if selected {
        Stroke::new(1.0, colors::CYAN_ACCENT)
    } else {
        Stroke::new(1.0, colors::STROKE_GREY)
    };

    let mut ret = None;

    // Use push_id to scope the contents of the list item
    ui.push_id(id, |ui| {
        egui::Frame::default()
            .fill(bg_color)
            .stroke(stroke)
            .corner_radius(egui::CornerRadius::ZERO)
            .inner_margin(4.0)
            .show(ui, |ui| {
                // Ensure full width
                ui.set_width(ui.available_width());
                ret = Some(add_contents(ui));
            });
    });

    // The closure is guaranteed to run, so ret will be Some
    ret.unwrap_or_else(|| unreachable!("Closure should have been executed"))
}
