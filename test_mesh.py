import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'Color32::from_gray\(30\)',
    r'''ui.visuals().window_fill'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'Stroke::new\(1\.0, Color32::GRAY\)',
    r'''ui.visuals().window_stroke'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'Stroke::new\(1\.0, Color32::from_white_alpha\(20\)\)',
    r'''Stroke::new(1.0, ui.visuals().text_color().linear_multiply(0.1))'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'egui::FontId::proportional\(12\.0\),\s*Color32::WHITE,',
    r'''egui::FontId::proportional(12.0),
        ui.visuals().strong_text_color(),'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'egui::FontId::proportional\(14\.0\),\s*Color32::GRAY,',
    r'''egui::FontId::proportional(14.0),
        ui.visuals().text_color().linear_multiply(0.6),'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'Color32::from_rgb\(255,\s*200,\s*100\)',
    r'''ui.visuals().strong_text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'Stroke::new\(2\.0, Color32::WHITE\)',
    r'''Stroke::new(2.0, ui.visuals().text_color())'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/mesh.rs',
    r'egui::FontId::proportional\(10\.0\),\s*Color32::WHITE,',
    r'''egui::FontId::proportional(10.0),
        ui.visuals().strong_text_color(),'''
)
