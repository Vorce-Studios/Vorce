use crate::theme::colors;
use crate::widgets::icons::{AppIcon, IconManager};
use egui::{
    lerp, Color32, CornerRadius, Pos2, Rect, Sense, Stroke, Ui, Vec2, WidgetInfo, WidgetType,
};

/// Helper function to handle hold-to-confirm logic.
///
/// Returns a tuple: `(triggered, progress)`
/// - `triggered`: `true` if the hold action completed successfully.
/// - `progress`: Normalized progress (0.0 to 1.0) of the hold action.
pub fn check_hold_state(ui: &mut Ui, id: egui::Id, is_interacting: bool) -> (bool, f32) {
    let hold_duration = 0.6; // seconds

    // Use specific IDs for state storage to avoid collisions
    let start_time_id = id.with("start_time");
    let progress_id = id.with("progress");

    let mut start_time: Option<f64> = ui.data_mut(|d| d.get_temp(start_time_id));
    let mut triggered = false;
    let mut progress = 0.0;

    if is_interacting {
        let now = ui.input(|i| i.time);
        if start_time.is_none() {
            start_time = Some(now);
            ui.data_mut(|d| d.insert_temp(start_time_id, start_time));
        }

        let elapsed = now - start_time.unwrap_or(now);
        progress = (elapsed as f32 / hold_duration).clamp(0.0, 1.0);

        // Store progress for external visualization if needed
        ui.data_mut(|d| d.insert_temp(progress_id, progress));

        if progress >= 1.0 {
            triggered = true;
            ui.ctx().request_repaint(); // Force repaint to show the 1-frame trigger flash
            ui.data_mut(|d| d.remove_temp::<Option<f64>>(start_time_id)); // Reset
            ui.data_mut(|d| d.remove_temp::<f32>(progress_id));
        } else {
            ui.ctx().request_repaint(); // Animate
        }
    } else if start_time.is_some() {
        // Reset if released early
        ui.data_mut(|d| d.remove_temp::<Option<f64>>(start_time_id));
        ui.data_mut(|d| d.remove_temp::<f32>(progress_id));
    }

    (triggered, progress)
}

/// A safety button that requires holding down for 0.6s to trigger (Mouse or Keyboard)
pub fn hold_to_action_button(ui: &mut Ui, text: &str, color: Color32, hover_text: &str) -> bool {
    // Small button size
    let text_galley = ui.painter().layout_no_wrap(
        text.to_string(),
        egui::FontId::proportional(12.0),
        ui.visuals().text_color(),
    );
    let size = Vec2::new(text_galley.size().x + 20.0, 20.0);

    // Use Sense::click() for accessibility (focus/tab navigation)
    let (rect, response) = ui.allocate_at_least(size, Sense::click());

    // Accessibility info
    let a11y_label = if hover_text.is_empty() {
        format!("Hold to confirm {}", text)
    } else {
        format!("{} (Hold to confirm)", hover_text)
    };
    response.widget_info(|| WidgetInfo::labeled(WidgetType::Button, ui.is_enabled(), &a11y_label));

    // Use response.id for unique state storage to prevent collisions
    let state_id = response.id.with("hold_state");

    // Check inputs:
    // 1. Mouse/Touch: is_pointer_button_down_on()
    // 2. Keyboard: has_focus() && key_down(Space/Enter)
    let is_interacting = response.is_pointer_button_down_on()
        || (response.has_focus()
            && (ui.input(|i| i.key_down(egui::Key::Space) || i.key_down(egui::Key::Enter))));

    let (triggered, progress) = check_hold_state(ui, state_id, is_interacting);

    // --- Visuals ---
    let visuals = ui.style().interact(&response);
    let painter = ui.painter();

    // 1. Background
    painter.rect(
        rect,
        CornerRadius::ZERO,
        visuals.bg_fill,
        visuals.bg_stroke,
        egui::StrokeKind::Middle,
    );

    // Draw focus ring if focused
    if response.has_focus() {
        painter.rect_stroke(
            rect.expand(2.0),
            CornerRadius::ZERO,
            Stroke::new(1.0, ui.style().visuals.selection.stroke.color),
            egui::StrokeKind::Middle,
        );
    }

    // 2. Progress Fill
    if progress > 0.0 || triggered {
        let mut fill_rect = rect;
        let display_progress = if triggered { 1.0 } else { progress };
        fill_rect.max.x = rect.min.x + rect.width() * display_progress;
        let fill_color = if triggered {
            color.linear_multiply(0.8) // Flash brightly on completion
        } else {
            color.linear_multiply(0.4) // Transparent version of action color
        };
        painter.rect_filled(fill_rect, CornerRadius::ZERO, fill_color);
    }

    // 3. Text
    let text_color = if triggered { color } else { visuals.text_color() };
    painter.text(
        rect.center(),
        egui::Align2::CENTER_CENTER,
        text,
        egui::FontId::proportional(12.0),
        text_color,
    );

    // Tooltip
    if response.hovered() {
        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
    }

    if !hover_text.is_empty() {
        response.on_hover_text(format!("{} (Hold to confirm)", hover_text));
    } else {
        response.on_hover_text(format!("Hold to confirm {} (Mouse or Space/Enter)", text));
    }

    triggered
}

/// A safety icon button that requires holding down for 0.6s to trigger.
/// Visualizes progress with a ring overlay.
pub fn hold_to_action_icon(
    ui: &mut Ui,
    icon_manager: Option<&IconManager>,
    icon: AppIcon,
    size: f32,
    color: Color32,
    hover_text: &str,
) -> bool {
    let desired_size = Vec2::splat(size + 8.0); // Add padding for ring
    let (rect, response) = ui.allocate_at_least(desired_size, Sense::click());

    // Accessibility info
    let enabled = ui.is_enabled();
    let label = if hover_text.is_empty() {
        let icon_name =
            icon.file_name().replace("ultimate_", "").replace(".svg", "").replace("_", " ");
        format!("Hold to confirm {}...", icon_name)
    } else {
        format!("{} (Hold to confirm)", hover_text)
    };
    response.widget_info(move || WidgetInfo::labeled(WidgetType::Button, enabled, label.clone()));

    let state_id = response.id.with("hold_state");

    // Check inputs
    let is_interacting = response.is_pointer_button_down_on()
        || (response.has_focus()
            && (ui.input(|i| i.key_down(egui::Key::Space) || i.key_down(egui::Key::Enter))));

    let (triggered, progress) = check_hold_state(ui, state_id, is_interacting);

    // Visuals
    let painter = ui.painter();
    let center = rect.center();

    // Draw focus ring if focused
    if response.has_focus() {
        painter.rect_stroke(
            rect.expand(2.0),
            CornerRadius::ZERO,
            Stroke::new(1.0, ui.style().visuals.selection.stroke.color),
            egui::StrokeKind::Middle,
        );
    }

    // Draw Icon
    if let Some(mgr) = icon_manager {
        if let Some(texture) = mgr.get(icon) {
            let icon_rect = Rect::from_center_size(center, Vec2::splat(size));
            let tint = if response.hovered() || is_interacting {
                ui.visuals().strong_text_color()
            } else {
                colors::LIGHTER_GREY
            };
            painter.image(
                texture.id(),
                icon_rect,
                Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
                tint,
            );
        } else {
            // Fallback text if texture not found
            painter.text(
                center,
                egui::Align2::CENTER_CENTER,
                "?",
                egui::FontId::proportional(size),
                color,
            );
        }
    } else {
        // Fallback if no manager
        painter.text(
            center,
            egui::Align2::CENTER_CENTER,
            "!",
            egui::FontId::proportional(size),
            color,
        );
    }

    // Draw Progress Ring
    if progress > 0.0 || triggered {
        use std::f32::consts::TAU;
        let radius = size / 2.0 + 2.0;
        if triggered {
            painter.circle_filled(center, radius, color);
        } else {
            let stroke = Stroke::new(2.0, color);

            // Background ring (faint)
            painter.circle_stroke(center, radius, Stroke::new(2.0, color.linear_multiply(0.2)));

            // Better visual: Arc using points
            let start_angle = -TAU / 4.0; // Top
            let end_angle = start_angle + progress * TAU;
            let n_points = 32;
            let points: Vec<Pos2> = (0..=n_points)
                .map(|i| {
                    let t = i as f32 / n_points as f32;
                    let angle = lerp(start_angle..=end_angle, t);
                    center + Vec2::new(angle.cos(), angle.sin()) * radius
                })
                .collect();

            painter.add(egui::Shape::line(points, stroke));
        }
    }

    if response.hovered() {
        ui.ctx().set_cursor_icon(egui::CursorIcon::PointingHand);
    }

    if !hover_text.is_empty() {
        response.on_hover_text(format!("{} (Hold to confirm)", hover_text));
    } else {
        let icon_name =
            icon.file_name().replace("ultimate_", "").replace(".svg", "").replace("_", " ");
        response.on_hover_text(format!("Hold to confirm {}... (Mouse or Space/Enter)", icon_name));
    }

    triggered
}

pub fn draw_safety_radial_fill(
    painter: &egui::Painter,
    center: Pos2,
    radius: f32,
    progress: f32,
    color: Color32,
) {
    if progress > 0.0 {
        use std::f32::consts::TAU;
        let stroke = Stroke::new(2.0, color);

        // Background ring (faint)
        painter.circle_stroke(center, radius, Stroke::new(2.0, color.linear_multiply(0.2)));

        // Better visual: Arc using points
        let start_angle = -TAU / 4.0; // Top
        let end_angle = start_angle + progress * TAU;
        let n_points = 32;
        let points: Vec<Pos2> = (0..=n_points)
            .map(|i| {
                let t = i as f32 / n_points as f32;
                let angle = lerp(start_angle..=end_angle, t);
                center + Vec2::new(angle.cos(), angle.sin()) * radius
            })
            .collect();

        painter.add(egui::Shape::line(points, stroke));
    }
}
