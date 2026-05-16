use crate::theme::colors;
use egui::{Color32, Stroke, Ui};

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
    ret.expect("Closure should have been executed")
}

use crate::widgets::custom::hold_to_action_button;

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
    fn test_cyber_list_item() {
        test_ui(|ui| {
            let id = ui.id().with("test_list_item");
            cyber_list_item(ui, id, false, false, |ui| {
                ui.label("List item content");
            });
            cyber_list_item(ui, id.with("2"), true, false, |ui| {
                ui.label("List item content");
            });
            cyber_list_item(ui, id.with("3"), false, true, |ui| {
                ui.label("List item content");
            });
        });
    }
}
