import os

part_path = "crates/vorce-ui/src/editors/module_canvas/draw/part.rs"
search_path = "crates/vorce-ui/src/editors/module_canvas/draw/search.rs"

# Part.rs modification
with open(part_path, 'r') as f:
    content = f.read()

# Replace first instance
content = content.replace(
    "if socket.name.to_lowercase().contains(&type_name.to_lowercase())",
    "if utils::case_insensitive_contains(&socket.name, type_name)"
)

with open(part_path, 'w') as f:
    f.write(content)

# Search.rs modification
with open(search_path, 'r') as f:
    content = f.read()

content = content.replace(
    "name.contains(filter_lower) || type_name.to_lowercase().contains(filter_lower)",
    "name.contains(filter_lower) || utils::case_insensitive_contains(type_name, filter_lower)"
)

with open(search_path, 'w') as f:
    f.write(content)
