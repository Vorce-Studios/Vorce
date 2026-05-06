import re

with open('crates/vorce-render/src/preset.rs', 'r') as f:
    content = f.read()

content = content.replace(
    'metadata.name_lower = metadata.name.to_lowercase();\n        metadata.description_lower = metadata.description.to_lowercase();\n        metadata.tags_lower = metadata.tags.iter().map(|t| t.to_lowercase()).collect();',
    'metadata.name_lower = metadata.name.to_lowercase();\n        metadata.description_lower = metadata.description.to_lowercase();\n        metadata.tags_lower = metadata.tags.iter().map(|t| t.to_lowercase()).collect();'
)

# wait actually we don't need to patch render or control. the PR states "Wähle genau EINE kleine, gezielte Performance-Verbesserung"
