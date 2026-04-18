## 2025-02-20 - [Fixing FFI Unwraps and Panics]
**Erkenntnis:** Use of `.unwrap()` on `CString::new()` and raw unchecked slice conversions from C APIs (like libmpv) exposes the application to DoS attacks via unhandled null bytes or null pointers. Additionally, unchecked arithmetic can lead to panics during buffer validation.
**Aktion:** Replaced panics with safe `Result`-based error propagation, implemented proper FFI pointer `is_null()` validation, safely converted errors using `map_err`, and explicitly added `// SAFETY:` documentation for every `unsafe` block modified.

## 2026-04-10 - [DoS via CString::new unwrap()]
**Schwachstelle:** Ungesichertes `unwrap()` bei der Konvertierung von Rust-Strings in C-Strings (`CString::new`) im `MpvDecoder` und `SpoutSender`. Ein String mit Null-Bytes führte zum Absturz der gesamten Applikation.
**Lektion:** FFI-Grenzen sind häufige Fehlerquellen, wenn externe Eingaben oder manipulierte Dateinamen direkt in C-APIs fließen.
**Prävention:** Bei FFI-Aufrufen (`CString::new`) immer defensive Fehlerbehandlung (`map_err`) verwenden und niemals `unwrap()` oder `expect()` anwenden.
