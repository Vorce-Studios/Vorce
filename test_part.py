import re

def replace_in_file(filepath, search_regex, replacement):
    with open(filepath, 'r') as f:
        content = f.read()

    new_content = re.sub(search_regex, replacement, content, flags=re.MULTILINE | re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(new_content)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'painter\.rect_filled\(preview_rect,\s*0\.0,\s*Color32::from_gray\(15\)\);',
    r'''painter.rect_filled(preview_rect, 0.0, ui.visuals().window_fill.linear_multiply(0.5));'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'let category_color = Color32::from_white_alpha\(160\);',
    r'''let category_color = ui.visuals().text_color().linear_multiply(0.6);'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_gray\(180\),',
    r'''ui.visuals().text_color().linear_multiply(0.7),'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'painter\.rect_filled\(bar_bg,\s*2\.0\s*\*\s*canvas\.zoom,\s*Color32::from_gray\(30\)\);',
    r'''painter.rect_filled(bar_bg, 2.0 * canvas.zoom, ui.visuals().extreme_bg_color);'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'painter\.rect_filled\(meter_bg,\s*2\.0,\s*Color32::from_gray\(20\)\);',
    r'''painter.rect_filled(meter_bg, 2.0, ui.visuals().extreme_bg_color);'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Stroke::new\(1\.0,\s*Color32::from_white_alpha\(40\)\)',
    r'''Stroke::new(1.0, ui.visuals().text_color().linear_multiply(0.15))'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_gray\(20\)',
    r'''ui.visuals().extreme_bg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'if is_hovered \{ socket_color \} else \{ Color32::from_gray\(100\) \}',
    r'''if is_hovered { socket_color } else { ui.visuals().text_color().linear_multiply(0.4) }'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_gray\(230\)',
    r'''ui.visuals().text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::WHITE\.gamma_multiply\(180\.0 \* glow_intensity / 255\.0\)',
    r'''ui.visuals().strong_text_color().gamma_multiply(180.0 * glow_intensity / 255.0)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::WHITE\.gamma_multiply\(200\.0 \* pulse / 255\.0\)',
    r'''ui.visuals().strong_text_color().gamma_multiply(200.0 * pulse / 255.0)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'egui::Color32::YELLOW',
    r'''ui.visuals().warn_fg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'painter\.image\([^;]+Color32::WHITE,\s*\);',
    r'''painter.image(
            texture_id,
            preview_rect,
            Rect::from_min_max(Pos2::new(0.0, 0.0), Pos2::new(1.0, 1.0)),
            Color32::WHITE, // Keeping White for texture tinting to preserve hues
        );'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(255,\s*\(160\.0 \* glow_intensity\) as u8,\s*0,\s*255\)',
    r'''ui.visuals().warn_fg_color.linear_multiply(glow_intensity)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(0,\s*200,\s*255\)',
    r'''ui.visuals().selection.bg_fill'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(0,\s*210,\s*255,\s*32\)',
    r'''ui.visuals().selection.bg_fill.linear_multiply(0.1)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(255,\s*100,\s*220,\s*28\)',
    r'''ui.visuals().strong_text_color().linear_multiply(0.1)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(255,\s*170,\s*80,\s*38\)',
    r'''ui.visuals().warn_fg_color.linear_multiply(0.15)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(140,\s*255,\s*140,\s*24\)',
    r'''ui.visuals().strong_text_color().linear_multiply(0.1)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(190,\s*170,\s*255,\s*24\)',
    r'''ui.visuals().text_color().linear_multiply(0.1)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(180,\s*200,\s*255,\s*20\)',
    r'''ui.visuals().text_color().linear_multiply(0.08)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(255,\s*50,\s*50\)',
    r'''ui.visuals().error_fg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(255,\s*100,\s*100,\s*200\)',
    r'''ui.visuals().error_fg_color.linear_multiply(0.8)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(100,\s*255,\s*100\)',
    r'''ui.visuals().strong_text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(255,\s*200,\s*50\)',
    r'''ui.visuals().warn_fg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgba_unmultiplied\(255,\s*50,\s*50,\s*200\)',
    r'''ui.visuals().error_fg_color.linear_multiply(0.8)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(230,\s*225,\s*210\)',
    r'''ui.visuals().text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(200,\s*50,\s*50\)',
    r'''ui.visuals().error_fg_color'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(180,\s*40,\s*40\)',
    r'''ui.visuals().error_fg_color.linear_multiply(0.8)'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(0,\s*255,\s*100\)',
    r'''ui.visuals().strong_text_color()'''
)

replace_in_file(
    'crates/vorce-ui/src/editors/module_canvas/draw/part.rs',
    r'Color32::from_rgb\(255,\s*180,\s*0\)',
    r'''ui.visuals().warn_fg_color'''
)
