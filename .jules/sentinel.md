
## 2024-05-24 - Cross-Platform Path Traversal Bypass in Path::components()
**Vulnerability:** Windows-style path traversal payloads (`..\..\secret`) bypass `std::path::Path::components()` validation when executed on non-Windows systems (like Linux/macOS servers) because backslashes are not treated as path separators.
**Learning:** Rust's `Path` behaves according to the target OS. When validating input that might originate from or target a different OS, you cannot rely solely on native path parsing.
**Prevention:** Always normalize path separators (e.g., `.replace("\\", "/")`) before using `Path::components()` for security validation, or manually scan for both `/../` and `\..\`.
## 2024-05-24 - Missing Target Validation in apply_control
**Vulnerability:** The `apply_control` method validated the `ControlValue` for path traversal, but failed to call `target.validate()` on the `ControlTarget`, allowing potentially malicious target names with path traversals or control characters to bypass validation.
**Learning:** Validation methods on complex types must be explicitly called at the boundary where they are ingested or applied; do not assume they are implicitly validated.
**Prevention:** Always trace the data flow of user-controlled complex types (like enums with string variants) and ensure their inherent `.validate()` methods are executed before the data is used.
## 2024-05-24 - DoS via Memory Exhaustion in File I/O
**Vulnerability:** Loading large files entirely into memory using `read_to_end` or `read_to_string`.
**Learning:** `std::io::copy` must be used for file transfers instead of buffering into memory arrays.
**Prevention:** Use streaming I/O whenever possible.
## 2024-05-18 - Avoid Legacy XSS-Protection Anti-Pattern
**Vulnerability:** The HTTP API server in `crates/mapmap-control/src/web/server.rs` used the legacy header `X-XSS-Protection: 1; mode=block`. This feature is deprecated across modern browsers and is considered an anti-pattern as it can introduce new vulnerabilities like selective blocklist-based side-channel leaks.
**Learning:** Using `X-XSS-Protection: 1; mode=block` can sometimes allow attackers to disable legitimate scripts on the page by tricking the browser's XSS auditor into blocking them (an XSS-Auditor bypass/denial-of-service). Modern applications should rely exclusively on Content Security Policy (CSP).
**Prevention:** Always set `X-XSS-Protection: 0` to disable the legacy auditor and enforce strong CSP headers instead for XSS defense-in-depth.
## 2024-04-10 - [DoS by NaN via Float Sorting] **Schwachstelle:** Ungeprüftes `.unwrap()` bei `.partial_cmp()` von f32/f64 in `animation.rs` und `mapping.rs`. Wenn ein `NaN` Wert die Sortierung erreicht (z.B. durch Fehlerhafte Trigger/Netzwerk Inputs), würde die gesamte Applikation abstürzen (Denial of Service). **Lektion:** `.partial_cmp()` auf Floats gibt bei `NaN` Vergleichen `None` zurück, was mit `.unwrap()` direkt zum Panic führt. **Prävention:** Immer einen sicheren Fallback wie `.unwrap_or(std::cmp::Ordering::Equal)` verwenden, wenn Floats in Rust sortiert werden, da sich `NaN` wie ein normaler Float-Wert im Memory ausbreiten kann.
