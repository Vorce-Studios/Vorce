with open('crates/vorce-ui/src/panels/shortcuts_panel.rs', 'r') as f:
    data = f.read()

data = data.replace('s.description_lower.contains(&filter_lower) || s.shortcut_str_lower.contains(&filter_lower)', 's.description_lower.contains(&filter_lower)\n                    || s.shortcut_str_lower.contains(&filter_lower)')

with open('crates/vorce-ui/src/panels/shortcuts_panel.rs', 'w') as f:
    f.write(data)
