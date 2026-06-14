use crate::theme::colors;
use crate::widgets::icons::{AppIcon, IconManager};
use egui::{
    Color32, CornerRadius, Pos2, Rect, Response, Sense, Stroke, Ui, Vec2, WidgetInfo, WidgetType,
};

use super::hold_action::hold_to_action_button;

pub fn styled_button(ui: &mut Ui, text: &str, _active: bool) -> Response {
    ui.button(text)
}

/// Simple Icon Button Helper (Stateless)
pub fn icon_button_simple(
    ui: &mut Ui,
    icon_manager: Option<&IconManager>,
    icon: AppIcon,
    size: f32,
    hover_text: &str,
) -> Response {
    let desired_size = Vec2::splat(size + 8.0); // Padding
    let (rect, response) = ui.allocate_at_least(desired_size, Sense::click());

    // Accessibility info
    let enabled = ui.is_enabled();
    let label = if hover_text.is_empty() {
        icon.file_name().replace("ultimate_", "").replace(".svg", "").replace("_", " ")
    } else {
        hover_text.to_string()
    };
    response.widget_info(move || WidgetInfo::labeled(WidgetType::Button, enabled, label.clone()));

    let visuals = ui.style().interact(&response);

    // Background fill logic
    let bg_fill =
        if response.hovered() { ui.visuals().widgets.hovered.bg_fill } else { visuals.bg_fill };

    // Stroke logic
    let stroke =
        if response.hovered() { ui.visuals().widgets.hovered.bg_stroke } else { visuals.bg_stroke };

    ui.painter().rect(rect, CornerRadius::ZERO, bg_fill, stroke, egui::StrokeKind::Middle);

    // Draw focus ring if focused
    if response.has_focus() {
        ui.painter().rect_stroke(
            rect.expand(2.0),
            CornerRadius::ZERO,
            Stroke::new(1.0, ui.style().visuals.selection.stroke.color),
            egui::StrokeKind::Middle,
        );
    }

    // Draw Icon
    if let Some(mgr) = icon_manager {
        if let Some(texture) = mgr.get(icon) {
            let icon_rect = Rect::from_center_size(rect.center(), Vec2::splat(size));
            let tint = if response.hovered() {
                ui.visuals().strong_text_color()
            } else {
                ui.visuals().text_color()
            };
            ui.painter().image(
                texture.id(),
                icon_rect,
                Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
                tint,
            );
        } else {
            // Fallback text if texture not found
            ui.painter().text(
                rect.center(),
                egui::Align2::CENTER_CENTER,
                "?",
                egui::FontId::proportional(size),
                ui.visuals().text_color(),
            );
        }
    } else {
        // Fallback if no manager
        ui.painter().text(
            rect.center(),
            egui::Align2::CENTER_CENTER,
            "!",
            egui::FontId::proportional(size),
            ui.visuals().text_color(),
        );
    }

    response.on_hover_text(hover_text)
}

/// Generic Icon Button Helper
pub fn icon_button(
    ui: &mut Ui,
    text: &str,
    hover_color: Color32,
    active_color: Color32,
    is_active: bool,
) -> Response {
    let desired_size = Vec2::new(24.0, 24.0);
    let (rect, response) = ui.allocate_at_least(desired_size, Sense::click());

    // Accessibility info
    response.widget_info(|| WidgetInfo::labeled(WidgetType::Button, ui.is_enabled(), text));

    let visuals = ui.style().interact(&response);

    // Background fill logic
    let bg_fill = if is_active {
        active_color
    } else if response.hovered() && hover_color != Color32::TRANSPARENT {
        hover_color
    } else if response.hovered() {
        ui.visuals().widgets.hovered.bg_fill
    } else {
        visuals.bg_fill
    };

    // Stroke logic
    let stroke = if is_active { Stroke::new(1.0, active_color) } else { visuals.bg_stroke };

    ui.painter().rect(rect, CornerRadius::ZERO, bg_fill, stroke, egui::StrokeKind::Middle);

    // Draw focus ring if focused
    if response.has_focus() {
        ui.painter().rect_stroke(
            rect.expand(2.0),
            CornerRadius::ZERO,
            Stroke::new(1.0, ui.style().visuals.selection.stroke.color),
            egui::StrokeKind::Middle,
        );
    }

    let text_pos = rect.center();

    // Text color logic: Black if active or hovered with color
    let is_colored = is_active || (response.hovered() && hover_color != Color32::TRANSPARENT);
    let text_color = if is_colored { Color32::BLACK } else { ui.visuals().text_color() };

    ui.painter().text(
        text_pos,
        egui::Align2::CENTER_CENTER,
        text,
        egui::FontId::proportional(14.0),
        text_color,
    );

    response
}

/// Simple Icon Button that uses an AppIcon and IconManager (Compact, fixed size)
pub fn icon_button_compact(
    ui: &mut Ui,
    icon_manager: Option<&IconManager>,
    icon: AppIcon,
    hover_text: &str,
) -> Response {
    let size = 20.0;
    let desired_size = Vec2::splat(size + 4.0);
    let (rect, response) = ui.allocate_at_least(desired_size, Sense::click());

    // Accessibility info
    let enabled = ui.is_enabled();
    let label = if hover_text.is_empty() {
        icon.file_name().replace("ultimate_", "").replace(".svg", "").replace("_", " ")
    } else {
        hover_text.to_string()
    };
    response.widget_info(move || WidgetInfo::labeled(WidgetType::Button, enabled, label.clone()));

    let visuals = ui.style().interact(&response);
    let painter = ui.painter();

    // Background
    let bg_fill = if response.hovered() || response.has_focus() {
        ui.visuals().widgets.hovered.bg_fill
    } else {
        visuals.bg_fill
    };

    painter.rect(rect, CornerRadius::ZERO, bg_fill, visuals.bg_stroke, egui::StrokeKind::Middle);

    // Draw focus ring if focused
    if response.has_focus() {
        painter.rect_stroke(
            rect.expand(2.0),
            CornerRadius::ZERO,
            Stroke::new(1.0, ui.style().visuals.selection.stroke.color),
            egui::StrokeKind::Middle,
        );
    }

    let center = rect.center();

    // Draw Icon
    if let Some(mgr) = icon_manager {
        if let Some(texture) = mgr.get(icon) {
            let icon_rect = Rect::from_center_size(center, Vec2::splat(size));
            let tint = if response.hovered() || response.has_focus() {
                ui.visuals().strong_text_color()
            } else {
                ui.visuals().text_color()
            };
            painter.image(
                texture.id(),
                icon_rect,
                Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
                tint,
            );
        } else {
            painter.text(
                center,
                egui::Align2::CENTER_CENTER,
                "?",
                egui::FontId::proportional(size),
                visuals.text_color(),
            );
        }
    } else {
        painter.text(
            center,
            egui::Align2::CENTER_CENTER,
            "!",
            egui::FontId::proportional(size),
            visuals.text_color(),
        );
    }

    if !hover_text.is_empty() {
        response.on_hover_text(hover_text)
    } else {
        response
    }
}

pub fn bypass_button(ui: &mut Ui, active: bool) -> Response {
    icon_button(ui, "B", Color32::TRANSPARENT, colors::WARN_COLOR, active)
        .on_hover_text("Bypass Layer")
}

pub fn solo_button(ui: &mut Ui, active: bool) -> Response {
    icon_button(ui, "S", Color32::TRANSPARENT, colors::MINT_ACCENT, active)
        .on_hover_text("Solo Layer")
}

pub fn param_button(ui: &mut Ui) -> Response {
    icon_button(ui, "P", colors::CYAN_ACCENT, colors::CYAN_ACCENT, false)
}

pub fn duplicate_button(ui: &mut Ui) -> Response {
    icon_button(ui, "D", colors::CYAN_ACCENT, colors::CYAN_ACCENT, false)
        .on_hover_text("Duplicate Layer")
}

pub fn delete_button(ui: &mut Ui) -> bool {
    hold_to_action_button(ui, "🗑", colors::ERROR_COLOR, "Delete")
}

pub fn lock_button(ui: &mut Ui, active: bool) -> Response {
    let active_color = colors::ERROR_COLOR;
    icon_button(ui, "🔒", Color32::TRANSPARENT, active_color, active).on_hover_text(if active {
        "Unlock"
    } else {
        "Lock"
    })
}

pub fn move_up_button(ui: &mut Ui) -> Response {
    icon_button(ui, "⏶", Color32::TRANSPARENT, Color32::TRANSPARENT, false).on_hover_text("Move Up")
}

pub fn move_down_button(ui: &mut Ui) -> Response {
    icon_button(ui, "⏷", Color32::TRANSPARENT, Color32::TRANSPARENT, false)
        .on_hover_text("Move Down")
}
