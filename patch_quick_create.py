import re

with open('crates/vorce-ui/src/editors/module_canvas/draw/quick_create.rs', 'r') as f:
    content = f.read()

content = content.replace(
    'let filter_lower = canvas.quick_create_filter.to_lowercase();\n    let filtered_items: Vec<&utils::NodeCatalogItem> = catalog\n        .iter()\n        .filter(|item| {\n            if filter_lower.is_empty() {\n                true\n            } else {\n                item.label_lower.contains(&filter_lower) || item.search_tags.contains(&filter_lower)\n            }\n        })',
    'let filtered_items: Vec<&utils::NodeCatalogItem> = catalog\n        .iter()\n        .filter(|item| {\n            let Some(filter_lower) = &canvas.quick_create_filter_lower else {\n                return true;\n            };\n            item.label_lower.contains(filter_lower) || item.search_tags.contains(filter_lower)\n        })'
)

content = content.replace(
    'let response = ui.add(\n                egui::TextEdit::singleline(&mut canvas.quick_create_filter)\n                    .hint_text("Type to create...")\n                    .lock_focus(true),\n            );',
    'let response = ui.add(\n                egui::TextEdit::singleline(&mut canvas.quick_create_filter)\n                    .hint_text("Type to create...")\n                    .lock_focus(true),\n            );\n            if response.changed() {\n                canvas.quick_create_filter_lower = (!canvas.quick_create_filter.is_empty()).then(|| canvas.quick_create_filter.to_lowercase());\n            }'
)

with open('crates/vorce-ui/src/editors/module_canvas/draw/quick_create.rs', 'w') as f:
    f.write(content)
