## 2025-02-20 - [Fixing FFI Unwraps and Panics]
**Erkenntnis:** Use of `.unwrap()` on `CString::new()` and raw unchecked slice conversions from C APIs (like libmpv) exposes the application to DoS attacks via unhandled null bytes or null pointers. Additionally, unchecked arithmetic can lead to panics during buffer validation.
**Aktion:** Replaced panics with safe `Result`-based error propagation, implemented proper FFI pointer `is_null()` validation, safely converted errors using `map_err`, and explicitly added `// SAFETY:` documentation for every `unsafe` block modified.
