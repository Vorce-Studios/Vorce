import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/connections.rs',
    r'\(3\.0 \* canvas\.zoom, Color32::WHITE, 8\.0 \* canvas\.zoom\)',
    r'''(3.0 * canvas.zoom, ui.visuals().strong_text_color(), 8.0 * canvas.zoom)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/connections.rs',
    r'Color32::from_rgba_unmultiplied\(255,\s*255,\s*255,\s*150\)',
    r'''ui.visuals().strong_text_color().linear_multiply(0.6)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/connections.rs',
    r'color: Color32::WHITE,',
    r'''color: ui.visuals().strong_text_color(),'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/connections.rs',
    r'Color32::RED',
    r'''ui.visuals().error_fg_color'''
)
