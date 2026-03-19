//! Styled UI Panel
//!
//! Provides a consistent frame and background for UI panels.

use egui::{Stroke, Style, Ui};

pub struct StyledPanel {
    title: String,
}

impl StyledPanel {
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
        }
    }

    pub fn show<R>(self, ui: &mut Ui, add_contents: impl FnOnce(&mut Ui) -> R) -> R {
        let frame = egui::Frame {
            fill: crate::theme::colors::DARK_GREY,
            corner_radius: egui::CornerRadius::ZERO,
            inner_margin: egui::Margin::same(8),
            outer_margin: egui::Margin::same(0),
            stroke: Stroke::new(1.0, crate::theme::colors::STROKE_GREY),
            ..Default::default()
        };

        frame
            .show(ui, |ui| {
                ui.vertical(|ui| {
                    render_panel_header(ui, &self.title, |_| {});
                    add_contents(ui)
                })
                .inner
            })
            .inner
    }
}

/// Create a standard "Cyber Dark" panel frame
pub fn cyber_panel_frame(_style: &Style) -> egui::Frame {
    egui::Frame {
        fill: crate::theme::colors::DARK_GREY,
        corner_radius: egui::CornerRadius::ZERO, // Sharp corners
        inner_margin: egui::Margin::same(0),     // Removed inner margin to let header touch edges
        stroke: Stroke::new(1.0, crate::theme::colors::STROKE_GREY),
        ..Default::default()
    }
}

/// Render a standard panel header with title and optional right-side content
pub fn render_panel_header<R>(
    ui: &mut Ui,
    title: &str,
    add_contents: impl FnOnce(&mut Ui) -> R,
) -> R {
    egui::Frame::default()
        .fill(crate::theme::colors::LIGHTER_GREY)
        .inner_margin(egui::Margin::symmetric(8, 4))
        .corner_radius(egui::CornerRadius::ZERO)
        .stroke(egui::Stroke {
            width: 1.0,
            color: crate::theme::colors::STROKE_GREY,
        })
        .show(ui, |ui| {
            ui.set_width(ui.available_width());

            // Allocate some exact space at the top-left to get the starting position for the stripe
            let start_rect = ui.min_rect();

            let response = ui.horizontal(|ui| {
                // Add subtle left padding horizontally to distance text from the accent stripe
                ui.add_space(8.0);

                ui.strong(title);
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    add_contents(ui)
                })
                .inner
            });

            // Calculate stripe height using the actual height of the laid-out content
            let header_rect = response.response.rect;
            let stripe_rect = egui::Rect::from_min_size(
                egui::Pos2::new(start_rect.min.x, header_rect.min.y),
                egui::Vec2::new(2.0, header_rect.height()),
            );

            // Draw the 2px visual accent stripe on the left edge for the Cyber Dark theme
            ui.painter().rect_filled(
                stripe_rect,
                egui::CornerRadius::ZERO,
                crate::theme::colors::CYAN_ACCENT,
            );

            response.inner
        })
        .inner
}
