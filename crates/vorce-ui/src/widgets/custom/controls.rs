use crate::theme::colors;
use egui::{
    lerp, Color32, CornerRadius, Key, Pos2, Rect, Response, Sense, Stroke, Ui, Vec2, WidgetInfo,
    WidgetType,
};

pub fn colored_progress_bar(ui: &mut Ui, value: f32) -> Response {
    ui.add(egui::ProgressBar::new(value).show_percentage())
}

pub fn styled_slider(
    ui: &mut Ui,
    value: &mut f32,
    range: std::ops::RangeInclusive<f32>,
    default_value: f32,
) -> Response {
    let desired_size = Vec2::new(ui.available_width(), 20.0);
    let (rect, response) = ui.allocate_at_least(desired_size, Sense::click_and_drag());

    let visuals = ui.style().interact(&response);

    // Double-click to reset
    if response.double_clicked() {
        *value = default_value;
    } else if response.dragged() {
        let min = *range.start();
        let max = *range.end();
        if let Some(mouse_pos) = response.interact_pointer_pos() {
            let new_value = egui::remap_clamp(mouse_pos.x, rect.left()..=rect.right(), min..=max);
            *value = new_value;
        }
    } else if response.has_focus() {
        // Keyboard support
        let step = (*range.end() - *range.start()) / 100.0;
        let small_step = step * 0.1;
        let large_step = step * 10.0;

        let mut new_value = *value;

        if ui.input(|i| i.key_pressed(Key::ArrowLeft)) {
            let s = if ui.input(|i| i.modifiers.shift) {
                large_step
            } else if ui.input(|i| i.modifiers.ctrl) {
                small_step
            } else {
                step
            };
            new_value -= s;
        }
        if ui.input(|i| i.key_pressed(Key::ArrowRight)) {
            let s = if ui.input(|i| i.modifiers.shift) {
                large_step
            } else if ui.input(|i| i.modifiers.ctrl) {
                small_step
            } else {
                step
            };
            new_value += s;
        }

        *value = new_value.clamp(*range.start(), *range.end());
    }

    ui.painter().rect(
        rect,
        CornerRadius::ZERO,
        colors::DARKER_GREY, // Track background
        visuals.bg_stroke,
        egui::StrokeKind::Middle,
    );

    // Draw focus ring if focused
    if response.has_focus() {
        ui.painter().rect_stroke(
            rect.expand(2.0),
            CornerRadius::ZERO,
            Stroke::new(1.0, ui.style().visuals.selection.stroke.color),
            egui::StrokeKind::Middle,
        );
    }

    let t = (*value - *range.start()) / (*range.end() - *range.start());
    let fill_rect = Rect::from_min_max(
        rect.min,
        Pos2::new(lerp((rect.left())..=(rect.right()), t.clamp(0.0, 1.0)), rect.max.y),
    );

    // Accent color logic
    let is_changed = (*value - default_value).abs() > 0.001;
    let fill_color =
        if is_changed { colors::CYAN_ACCENT } else { colors::CYAN_ACCENT.linear_multiply(0.7) };

    ui.painter().rect(
        fill_rect,
        CornerRadius::ZERO,
        fill_color,
        Stroke::new(0.0, Color32::TRANSPARENT),
        egui::StrokeKind::Middle,
    );

    // Value Text
    let text = format!("{:.2}", value);
    let text_color = if response.hovered() || response.dragged() {
        ui.visuals().strong_text_color()
    } else if is_changed {
        colors::CYAN_ACCENT
    } else {
        colors::STROKE_GREY
    };

    ui.painter().text(
        rect.center(),
        egui::Align2::CENTER_CENTER,
        text,
        egui::FontId::proportional(12.0),
        text_color,
    );

    // Accessibility
    response.widget_info(|| {
        let mut info = WidgetInfo::labeled(WidgetType::Slider, ui.is_enabled(), "Slider");
        info.value = Some(*value as f64);
        info
    });

    response.context_menu(|ui| {
        if ui.button("Reset to Default").clicked() {
            *value = default_value;
            ui.close();
        }
    });

    response.on_hover_text(
        "Double-click to reset, Drag to adjust, Arrows to fine tune, Right-click for options",
    )
}

pub fn styled_slider_log(
    ui: &mut Ui,
    value: &mut f32,
    range: std::ops::RangeInclusive<f32>,
    default_value: f32,
) -> Response {
    let response = ui.add(egui::Slider::new(value, range).logarithmic(true));

    if response.double_clicked() {
        *value = default_value;
    }

    response.context_menu(|ui| {
        if ui.button("Reset to Default").clicked() {
            *value = default_value;
            ui.close();
        }
    });

    response.on_hover_text("Double-click to reset, Drag to adjust, Right-click for options")
}

pub fn styled_drag_value(
    ui: &mut Ui,
    value: &mut f32,
    speed: f32,
    range: std::ops::RangeInclusive<f32>,
    default_value: f32,
    prefix: &str,
    suffix: &str,
) -> Response {
    let is_changed = (*value - default_value).abs() > 0.001;

    // Use scope to customize spacing or style if needed
    let response =
        ui.add(egui::DragValue::new(value).speed(speed).range(range).prefix(prefix).suffix(suffix));

    if response.double_clicked() {
        *value = default_value;
    }

    // Visual feedback for changed value
    if is_changed {
        ui.painter().rect_stroke(
            response.rect.expand(1.0),
            CornerRadius::ZERO,
            Stroke::new(1.0, colors::CYAN_ACCENT),
            egui::StrokeKind::Middle,
        );
    }

    response.context_menu(|ui| {
        if ui.button("Reset to Default").clicked() {
            *value = default_value;
            ui.close();
        }
    });

    response.on_hover_text("Double-click to reset, Right-click for options")
}
