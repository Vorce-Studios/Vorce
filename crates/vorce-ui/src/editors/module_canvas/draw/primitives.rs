use egui::{Color32, Pos2, Rect, Stroke, Vec2};

pub fn draw_node_selection(
    painter: &egui::Painter,
    part_rect: Rect,
    handle_rect: Rect,
    handle_size: f32,
    zoom: f32,
    window_fill: Color32,
) {
    let highlight_rect = part_rect.expand(4.0 * zoom);
    painter.rect_stroke(
        highlight_rect,
        0.0,
        Stroke::new(2.0 * zoom, crate::theme::colors::CYAN_ACCENT),
        egui::StrokeKind::Middle,
    );

    painter.rect_filled(handle_rect, 0.0, crate::theme::colors::CYAN_ACCENT);
    painter.line_segment(
        [
            handle_rect.min + Vec2::new(3.0, handle_size - 3.0),
            handle_rect.min + Vec2::new(handle_size - 3.0, 3.0),
        ],
        Stroke::new(1.5, window_fill),
    );
}

pub fn draw_connection_preview(
    painter: &egui::Painter,
    start_pos: Pos2,
    pointer_pos: Pos2,
    color: Color32,
    preview_stroke: Stroke,
) {
    painter.line_segment([start_pos, pointer_pos], preview_stroke);
    painter.circle_filled(pointer_pos, 5.0, color);
}

pub fn draw_context_menu_bg(
    painter: &egui::Painter,
    menu_rect: Rect,
    stroke_color: Color32,
    window_fill: Color32,
) {
    painter.rect_filled(menu_rect, 4.0, window_fill.gamma_multiply(0.96));
    painter.rect_stroke(menu_rect, 4.0, Stroke::new(1.0, stroke_color), egui::StrokeKind::Middle);
}
