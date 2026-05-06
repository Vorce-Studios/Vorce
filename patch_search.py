import re

with open('crates/vorce-ui/src/editors/module_canvas/draw/search.rs', 'r') as f:
    content = f.read()

content = content.replace(
    'ui.text_edit_singleline(&mut canvas.search_filter);',
    'let response = ui.text_edit_singleline(&mut canvas.search_filter);\n                if response.changed() {\n                    canvas.search_filter_lower = (!canvas.search_filter.is_empty()).then(|| canvas.search_filter.to_lowercase());\n                }'
)

content = content.replace(
    'let filter_lower = canvas.search_filter.to_lowercase();\n            let matching_parts: Vec<_> = module\n                .parts\n                .iter()\n                .filter(|p| {\n                    if filter_lower.is_empty() {\n                        return true;\n                    }\n                    let name = utils::get_part_property_text(&p.part_type).to_lowercase();\n                    let (_, _, _, type_name) = utils::get_part_style(&p.part_type);\n                    name.contains(&filter_lower) || type_name.to_lowercase().contains(&filter_lower)\n                })',
    'let matching_parts: Vec<_> = module\n                .parts\n                .iter()\n                .filter(|p| {\n                    let Some(filter_lower) = &canvas.search_filter_lower else {\n                        return true;\n                    };\n                    let name = utils::get_part_property_text(&p.part_type).to_lowercase();\n                    let (_, _, _, type_name) = utils::get_part_style(&p.part_type);\n                    name.contains(filter_lower) || type_name.to_lowercase().contains(filter_lower)\n                })'
)

with open('crates/vorce-ui/src/editors/module_canvas/draw/search.rs', 'w') as f:
    f.write(content)
