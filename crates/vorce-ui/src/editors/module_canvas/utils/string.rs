#[inline]
pub fn case_insensitive_contains(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return true;
    }

    let needle_len = needle.len();
    if haystack.len() < needle_len {
        return false;
    }

    haystack.char_indices().any(|(i, _)| {
        let tail = &haystack[i..];
        tail.len() >= needle_len
            && tail.is_char_boundary(needle_len)
            && tail[..needle_len].eq_ignore_ascii_case(needle)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_case_insensitive_contains() {
        assert!(case_insensitive_contains("Hello World", "world"));
        assert!(case_insensitive_contains("Hello World", "WORLD"));
        assert!(case_insensitive_contains("Hello World", "Hello"));
        assert!(!case_insensitive_contains("Hello World", "foo"));
        assert!(case_insensitive_contains("Hello", ""));
    }
}
