use super::super::{state::ModuleCanvas, utils};
use egui::{Pos2, Rect, Ui, Vec2};
use vorce_core::module::VorceModule;

pub fn case_insensitive_contains(haystack: &str, needle: &str) -> bool {
    // If needle is empty it's always contained
    if needle.is_empty() {
        return true;
    }

    // Fast path: ASCII
    if haystack.is_ascii() && needle.is_ascii() {
        let needle_len = needle.len();
        let haystack_bytes = haystack.as_bytes();
        let needle_bytes = needle.as_bytes();

        if haystack_bytes.len() < needle_len {
            return false;
        }

        for i in 0..=(haystack_bytes.len() - needle_len) {
            let mut matches = true;
            for j in 0..needle_len {
                if !haystack_bytes[i + j].eq_ignore_ascii_case(&needle_bytes[j]) {
                    matches = false;
                    break;
                }
            }
            if matches {
                return true;
            }
        }
        return false;
    }

    // Fallback: Unicode
    haystack.to_lowercase().contains(needle)
}

pub fn draw_search_popup(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    canvas_rect: Rect,
    module: &mut VorceModule,
) {
    let popup_width = 300.0;
    let popup_height = 200.0;
    let popup_rect = Rect::from_min_size(
        Pos2::new(canvas_rect.center().x - popup_width / 2.0, canvas_rect.min.y + 50.0),
        Vec2::new(popup_width, popup_height),
    );

    let painter = ui.painter();
    let visuals = ui.visuals();
    painter.rect_filled(popup_rect, 4.0, visuals.window_fill);
    painter.rect_stroke(popup_rect, 0.0, visuals.window_stroke, egui::StrokeKind::Middle);

    let inner_rect = popup_rect.shrink(10.0);
    ui.scope_builder(egui::UiBuilder::new().max_rect(inner_rect), |ui| {
        ui.vertical(|ui| {
            ui.horizontal(|ui| {
                ui.label("🔍");
                let text_edit_response = ui.text_edit_singleline(&mut canvas.search_filter);
                if text_edit_response.changed() {
                    canvas.search_filter_lower = (!canvas.search_filter.is_empty())
                        .then(|| canvas.search_filter.to_lowercase());
                }
            });
            ui.add_space(8.0);


            let matching_parts: Vec<_> = module
                .parts
                .iter()
                .filter(|p| {
                    let Some(f) = canvas.search_filter_lower.as_deref() else {
                        return true;
                    };
                    let name = utils::get_part_property_text(&p.part_type);
                    let (_, _, _, type_name) = utils::get_part_style(&p.part_type);
                    case_insensitive_contains(&name, f) || case_insensitive_contains(type_name, f)

                })
                .take(6)
                .collect();

            egui::ScrollArea::vertical().max_height(120.0).show(ui, |ui| {
                for part in matching_parts {
                    let (_, _, icon, type_name) = utils::get_part_style(&part.part_type);
                    let label = format!(
                        "{} {} - {}",
                        icon,
                        type_name,
                        utils::get_part_property_text(&part.part_type)
                    );
                    if ui
                        .selectable_label(canvas.selected_parts.contains(&part.id), &label)
                        .clicked()
                    {
                        canvas.clear_selection();
                        canvas.selected_parts.push(part.id);
                        canvas.pan_offset =
                            Vec2::new(-part.position.0 + 200.0, -part.position.1 + 150.0);
                        canvas.show_search = false;
                    }
                }
            });
        });
    });
}
