import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'Color32::from_rgb\(0,\s*229,\s*255\)',
    r'''ui.visuals().selection.bg_fill'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'Color32::from_gray\(40\)',
    r'''ui.visuals().extreme_bg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'Color32::GREEN',
    r'''ui.visuals().strong_text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'Color32::RED',
    r'''ui.visuals().error_fg_color'''
)


replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'painter\.rect_filled\(box_rect,\s*4\.0,\s*Color32::from_rgba_unmultiplied\(30,\s*30,\s*40,\s*245\)\);',
    r'''painter.rect_filled(box_rect, 4.0, ui.visuals().window_fill);'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'Stroke::new\(1\.0, Color32::from_rgb\(200,\s*80,\s*80\)\)',
    r'''Stroke::new(1.0, ui.visuals().error_fg_color)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'Stroke::new\(1\.0, Color32::from_rgb\(80,\s*100,\s*150\)\)',
    r'''Stroke::new(1.0, ui.visuals().text_color().linear_multiply(0.5))'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/renderer.rs',
    r'\.color\(Color32::WHITE\)',
    r'''.color(ui.visuals().strong_text_color())'''
)
