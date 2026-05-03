import re

with open('crates/vorce-ui/src/view/media_browser.rs', 'r') as f:
    content = f.read()

# 1. Add field
content = re.sub(
    r'(    /// Search query\n    search_query: String,\n)',
    r'\1    /// Cached lowercased search query to prevent per-frame allocation\n    search_query_lower: Option<String>,\n',
    content
)

# 2. Add initialization
content = re.sub(
    r'(            search_query: String::new\(\),\n)',
    r'\1            search_query_lower: None,\n',
    content
)

# 3. Remove let query = ... in filtered_entries
content = re.sub(
    r'    fn filtered_entries\(&self\) -> Vec<\(usize, &MediaEntry\)> \{\n        let query = if !self\.search_query\.is_empty\(\) \{\n            Some\(self\.search_query\.to_lowercase\(\)\)\n        \} else \{\n            None\n        \};\n\n        self\.entries\n',
    r'    fn filtered_entries(&self) -> Vec<(usize, &MediaEntry)> {\n        self.entries\n',
    content
)

# 4. Use self.search_query_lower in filtered_entries
content = re.sub(
    r'                // Filter by search query\n                if let Some\(q\) = &query \{\n',
    r'                // Filter by search query\n                if let Some(q) = &self.search_query_lower {\n',
    content
)

# 5. Update search_query_lower on change
content = re.sub(
    r'                if search_response\.changed\(\) \{\n                    // Search query changed\n                \}\n',
    r'                if search_response.changed() {\n                    self.search_query_lower = if self.search_query.is_empty() {\n                        None\n                    } else {\n                        Some(self.search_query.to_lowercase())\n                    };\n                }\n',
    content
)

with open('crates/vorce-ui/src/view/media_browser.rs', 'w') as f:
    f.write(content)
