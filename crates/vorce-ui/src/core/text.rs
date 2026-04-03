/// Zero-allocation Unicode case-insensitive containment check
pub fn contains_ignore_case(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return true;
    }

    // Fast path: ASCII only fallback to avoid iterator overhead if possible
    // We only use this if both strings are purely ASCII to avoid the Unicode bug.
    if haystack.is_ascii() && needle.is_ascii() {
        if haystack.len() < needle.len() {
            return false;
        }
        let needle_bytes = needle.as_bytes();
        return haystack
            .as_bytes()
            .windows(needle_bytes.len())
            .any(|w| w.eq_ignore_ascii_case(needle_bytes));
    }

    // Full Unicode case-insensitive containment
    haystack.char_indices().any(|(i, _)| {
        let mut haystack_chars = haystack[i..].chars().flat_map(|c| c.to_lowercase());
        let mut needle_chars = needle.chars().flat_map(|c| c.to_lowercase());

        loop {
            match (haystack_chars.next(), needle_chars.next()) {
                (Some(h), Some(n)) if h == n => continue,
                (Some(_), Some(_)) => return false,
                (_, None) => return true,
                (None, Some(_)) => return false,
            }
        }
    })
}
