import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/diagnostics.rs',
    r'painter\.rect_filled\(popup_rect,\s*0\.0,\s*Color32::from_rgba_unmultiplied\(30,\s*35,\s*45,\s*245\)\);',
    r'''painter.rect_filled(popup_rect, 4.0, ui.visuals().window_fill);'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/diagnostics.rs',
    r'Stroke::new\(2\.0, Color32::from_rgb\(180,\s*100,\s*80\)\)',
    r'''Stroke::new(2.0, ui.visuals().window_stroke.color)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/diagnostics.rs',
    r'Color32::RED',
    r'''ui.visuals().error_fg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/diagnostics.rs',
    r'Color32::YELLOW',
    r'''ui.visuals().warn_fg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/diagnostics.rs',
    r'Color32::LIGHT_BLUE',
    r'''ui.visuals().text_color()'''
)
