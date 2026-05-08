## 2025-02-20 - [Fixing FFI Unwraps and Panics]
**Erkenntnis:** Use of `.unwrap()` on `CString::new()` and raw unchecked slice conversions from C APIs (like libmpv) exposes the application to DoS attacks via unhandled null bytes or null pointers. Additionally, unchecked arithmetic can lead to panics during buffer validation.
**Aktion:** Replaced panics with safe `Result`-based error propagation, implemented proper FFI pointer `is_null()` validation, safely converted errors using `map_err`, and explicitly added `// SAFETY:` documentation for every `unsafe` block modified.
## 2025-02-20 - [Fixing MCP JSON-RPC Unwraps and Panics]
**Erkenntnis:** Unsafe usage of `.unwrap()` on parsing responses from external JSON-RPC requests via the MCP server makes the application crash-prone (DoS) when encountering unexpected formats.
**Aktion:** Replaced unsafe `unwrap()` invocations with `.expect()` in tests with clear error messages, mitigating unexpected application crashes during interaction simulation. Replaced unsafe unwrap in custom UI widget with defensive `if let Some()` pattern.
