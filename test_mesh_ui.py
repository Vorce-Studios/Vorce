import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'Color32::from_rgba_premultiplied\(100,\s*100,\s*150,\s*50\)',
    r'''ui.visuals().selection.bg_fill.linear_multiply(0.2)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'Stroke::new\(1\.0,\s*Color32::from_rgb\(150,\s*150,\s*200\)\)',
    r'''Stroke::new(1.0, ui.visuals().text_color().linear_multiply(0.6))'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'Color32::from_rgb\(255,\s*200,\s*100\)',
    r'''ui.visuals().strong_text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'Color32::from_rgb\(200,\s*200,\s*200\)',
    r'''ui.visuals().text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'Stroke::new\(2\.0,\s*Color32::WHITE\)',
    r'''Stroke::new(2.0, ui.visuals().strong_text_color())'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'Stroke::new\(1\.0,\s*Color32::from_rgb\(100,\s*200,\s*255\)\)',
    r'''Stroke::new(1.0, ui.visuals().text_color())'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'Color32::from_rgb\(100,\s*200,\s*255\)',
    r'''ui.visuals().text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/mesh_editor/ui.rs',
    r'let color = Color32::from_rgb\(50,\s*50,\s*50\);',
    r'''let color = painter.ctx().global_style().visuals.text_color().linear_multiply(0.1);'''
)
