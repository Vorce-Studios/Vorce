import re

with open('crates/vorce-ui/src/editors/module_canvas/state.rs', 'r') as f:
    content = f.read()

content = content.replace(
    'pub search_filter: String,\n',
    'pub search_filter: String,\n    /// Cached lowercased search filter text\n    pub search_filter_lower: Option<String>,\n'
)

content = content.replace(
    'pub quick_create_filter: String,\n',
    'pub quick_create_filter: String,\n    /// Cached lowercased quick create filter text\n    pub quick_create_filter_lower: Option<String>,\n'
)

content = content.replace(
    'search_filter: String::new(),\n',
    'search_filter: String::new(),\n            search_filter_lower: None,\n'
)

content = content.replace(
    'quick_create_filter: String::new(),\n',
    'quick_create_filter: String::new(),\n            quick_create_filter_lower: None,\n'
)

with open('crates/vorce-ui/src/editors/module_canvas/state.rs', 'w') as f:
    f.write(content)
