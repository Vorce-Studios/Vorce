import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs',
    r'egui::Color32::from_rgb\(110,\s*235,\s*150\)',
    r'''ui.visuals().strong_text_color().linear_multiply(0.8)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/inspector/mod.rs',
    r'egui::Color32::from_rgb\(180,\s*180,\s*180\)',
    r'''ui.visuals().text_color().linear_multiply(0.6)'''
)
