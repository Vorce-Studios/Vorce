import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/search.rs',
    r'painter\.rect_filled\(popup_rect,\s*0\.0,\s*Color32::from_rgba_unmultiplied\(30,\s*30,\s*40,\s*240\)\);.*?painter\.rect_stroke\([^;]+\);',
    r'''let visuals = ui.visuals();
    painter.rect_filled(popup_rect, 4.0, visuals.window_fill);
    painter.rect_stroke(
        popup_rect,
        0.0,
        visuals.window_stroke,
        egui::StrokeKind::Middle,
    );'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/presets.rs',
    r'painter\.rect_filled\(popup_rect,\s*0\.0,\s*Color32::from_rgba_unmultiplied\(30,\s*35,\s*45,\s*245\)\);.*?painter\.rect_stroke\([^;]+\);',
    r'''let visuals = ui.visuals();
    painter.rect_filled(popup_rect, 4.0, visuals.window_fill);
    painter.rect_stroke(
        popup_rect,
        0.0,
        visuals.window_stroke,
        egui::StrokeKind::Middle,
    );'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/mini_map.rs',
    r'painter\.rect_filled\(map_rect,\s*0\.0,\s*Color32::from_rgba_unmultiplied\(30,\s*30,\s*40,\s*200\)\);.*?painter\.rect_stroke\([^;]+\);',
    r'''let visuals = &painter.ctx().global_style().visuals;
    painter.rect_filled(map_rect, 4.0, visuals.window_fill);
    painter.rect_stroke(
        map_rect,
        0.0,
        visuals.window_stroke,
        egui::StrokeKind::Middle,
    );'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/mini_map.rs',
    r'Stroke::new\(1\.5,\s*Color32::WHITE\)',
    r'Stroke::new(1.5, visuals.strong_text_color())'
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/grid.rs',
    r'let color = Color32::from_rgb\(40,\s*40,\s*40\);',
    r'''let visuals = &painter.ctx().global_style().visuals;
    let color = visuals.text_color().linear_multiply(0.05);'''
)
