import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/inspector/source.rs',
    r'Color32::from_rgb\(100,\s*255,\s*150\)',
    r'''ui.visuals().strong_text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/inspector/source.rs',
    r'Color32::from_rgb\(200,\s*200,\s*200\)',
    r'''ui.visuals().text_color()'''
)
