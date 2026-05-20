use crate::AppUI;
use egui::Context;

pub fn render_stats_overlay(app_ui: &mut AppUI, ctx: &Context, fps: f32, frame_time_ms: f32) {
    if !app_ui.show_stats {
        return;
    }

    egui::Area::new(egui::Id::new("performance_overlay"))
        .anchor(egui::Align2::RIGHT_TOP, [-10.0, 50.0])
        .order(egui::Order::Foreground)
        .interactable(false)
        .show(ctx, |ui| {
            egui::Frame::default()
                .fill(crate::theme::colors::DARKER_GREY.linear_multiply(0.9))
                .corner_radius(egui::CornerRadius::ZERO)
                .stroke(egui::Stroke::new(1.0, crate::theme::colors::STROKE_GREY))
                .inner_margin(egui::Margin::symmetric(16, 8))
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        ui.label(
                            egui::RichText::new(format!("FPS: {:.0}", fps))
                                .color(crate::theme::colors::MINT_ACCENT)
                                .strong(),
                        );
                        ui.separator();
                        ui.label(
                            egui::RichText::new(format!("{:.1}ms", frame_time_ms))
                                .color(crate::theme::colors::CYAN_ACCENT),
                        );
                    });
                });
        });
}

pub fn render_stats(app_ui: &mut AppUI, ctx: &Context, fps: f32, frame_time_ms: f32) {
    render_stats_overlay(app_ui, ctx, fps, frame_time_ms);
}
