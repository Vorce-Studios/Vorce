## 2025-05-24 - DoS via Option::unwrap() in ffmpeg scaler

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im Media-Decoder (`crates/vorce-media/src/decoder.rs` auf Zeile 430), wenn die gecachte Skalierungsvariable (`SCALER_CACHE`) zurÃ¼ckgegeben wurde.

**Lektion:** Falls das Neu-Anlegen des FFmpeg-Scalers fehlschlÃ¤gt, aber das Error-Handling oder der Status des Objektes nicht sicher abgefangen wird, fÃ¼hrt dies zu einem direkten Absturz durch Panic (Denial of Service).

**PrÃ¤vention:** Optionen und Caches sollten immer mit Pattern Matching oder `if let Some()` / `let Some() = else {}` sicher aufgelÃ¶st werden. Wenn der Zustand ungÃ¼ltig ist, sollte ein sauber gekapselter Fehlerwert (wie `MediaError::DecoderError`) zurÃ¼ckgeliefert werden.


## 2025-05-24 - DoS via Option::unwrap() in ping-pong buffer

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich in der `apply()` Funktion des Effect Chain Renderers (`crates/vorce-render/src/effect_chain_renderer/apply.rs`), wenn auf den Ping-Pong-Buffer zugegriffen wurde.
**Lektion:** Wenn `self.ping_pong` aufgrund von Fehlern im Backend (z. B. Out-of-Memory oder invaliden GrÃ¶ÃŸen) auf `None` bleibt, fÃ¼hrt die AusfÃ¼hrung der Render-Pipeline zum sofortigen Absturz (DoS).
**PrÃ¤vention:** Bei kritischen Render-Pfaden mÃ¼ssen Resourcen sicher mit `if let Some()` oder pattern matching entpackt werden. SchlÃ¤gt dies fehl, kann der Render-Pass sicher Ã¼bersprungen oder mit einer Warnung abgebrochen werden, ohne die gesamte Applikation zum Absturz zu bringen.

## 2025-05-24 - [CRITICAL] Overly Permissive CORS Policy

**Schwachstelle:** Die CORS-Konfiguration erlaubte explizit den Wildcard-Origin `*` (`tower_http::cors::Any`), wenn dieser in der Konfiguration vorhanden war. Dies ermÃ¶glichte es beliebigen Webseiten, Anfragen an die Control-API zu stellen.

**Lektion:** CORS-Policies sollten niemals standardmÃ¤ÃŸig oder durch einfache Konfiguration Wildcards erlauben, insbesondere bei APIs, die sensitive Anfragen ausfÃ¼hren kÃ¶nnen.

**PrÃ¤vention:** Wildcards in CORS-Einstellungen sollten im Code explizit abgefangen und ignoriert werden. Erlaubte Origins mÃ¼ssen als spezifische, vertrauenswÃ¼rdige Domains konfiguriert werden.

## 2025-05-24 - DoS via Option::unwrap() in mpv_decoder

**Schwachstelle:** Zwei `unwrap()` Aufrufe befanden sich im Media-Decoder (`crates/vorce-media/src/mpv_decoder.rs` auf Zeilen 88 und 89) bei der Erstellung von `CString` aus String-Literalen.

**Lektion:** Obwohl die verwendeten String-Literale keine Null-Bytes enthalten und die Aufrufe in der Praxis sicher sind, kann ein versehentliches Ã„ndern oder dynamisches Erzeugen dieser Strings ohne Null-PrÃ¼fung zu Paniken und damit zum Absturz der gesamten Anwendung fÃ¼hren.

**PrÃ¤vention:** Verwende stattdessen sauberes Error Handling und fange Fehler elegant ab, z.B. durch `map_err`, das zu einem `MediaError::DecoderError` aufgelÃ¶st wird.

## 2025-05-24 - DoS via Option::unwrap() in media_library.rs tests

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im `test_media_library_limit` Test in `crates/vorce-core/src/media_library.rs` beim Erstellen von Verzeichnissen und Dateien.

**Lektion:** Wenn Fehler beim Erstellen von Verzeichnissen oder Dateien durch unwrap() ignoriert werden, fÃ¼hrt dies zu einem direkten Absturz durch Panic. Auch in Tests ist es besser, Fehler sauber mit `Result` zurÃ¼ckzugeben.

**PrÃ¤vention:** Verwende `Result` in Test-Signaturen und `?` zur Propagierung von Dateisystem-Fehlern anstelle von `unwrap()`.

## 2025-02-27 - [Security] Defense-in-Depth against WGSL Codegen Panics
**Schwachstelle:** The WGSL codegen implementation heavily relied on `.expect()` and `.unwrap()` which would cause the application to panic if shader graphs encountered unexpected types, parsing errors, or validation issues.
**Lektion:** Robust error handling is crucial for operations dependent on user input and serialized project files to prevent denial-of-service vulnerabilities. 
**PrÃ¤vention:** Use `.map_err()` to propagate errors up the call stack, explicitly defining error types like `CodegenError` where appropriate.
## 2025-01-20 - [Denial of Service (DoS)] **Schwachstelle:** `expect()` calls exist in `vorce-media/src/pipeline.rs` and `vorce-render/src/mesh_buffer_cache.rs` and `vorce-render/src/texture.rs`. **Lektion:** Code relied on expect() which can panic and cause DoS. **Prävention:** Use safe error handling or fallback defaults.

## 2025-05-24 - [HIGH] Path Traversal in Project Loader

**Schwachstelle:** `load_project` in `crates/vorce-io/src/project.rs` hat Dateipfade nicht auf `..` Komponenten validiert, wodurch Path Traversal beim Laden von Projekten mÃ¶glich war.
**Lektion:** Es fehlte eine Validierungsschicht zwischen externen Pfaden und dem Dateisystemzugriff.
**PrÃ¤vention:** Bei jeglichem Einlesen von Dateien über externe oder dynamische Pfade muss vor dem Aufruf von `File::open` oder `fs::read` zwingend eine Validierung der Pfadkomponenten stattfinden, idealerweise durch den Ausschluss von `Component::ParentDir` oder eine strikte Sandboxing-Architektur.

## 2024-05-18 - [Path Traversal Bypass]
**Schwachstelle:** Path Traversal checks using `std::path::Component::ParentDir` were bypassed on non-Windows platforms when paths contained Windows-style separators (e.g. `..\..\evil.mapmap`).
**Lektion:** `std::path::Path` parsing behavior depends on the target OS. On Linux, `\` is a valid filename character, so `..\` is parsed as a single component name, not a directory traversal.
**Prävention:** Always normalize path separators (e.g., `.replace("\\", "/")`) before performing traversal checks across all OS targets.

## 2025-05-24 - Path Traversal Mitigation in Media Decoders
**Schwachstelle:** The media decoders in `vorce-media` (e.g., `StillImageDecoder`, `MpvDecoder`, `GifDecoder`, `ImageSequenceDecoder`, `RealFFmpegDecoder`) loaded files from disk without explicitly validating whether the given path contained parent directory traversal components (`..`).
**Lektion:** While some path traversal protections existed at higher levels (like the project loading and MCP tools), the media decoding layer itself remained unprotected, allowing potential arbitrary file reads if external input bypassed higher-level checks.
**Prävention:** Add a defense-in-depth validation check directly inside the `open()` methods of media decoders, rejecting any paths that contain `std::path::Component::ParentDir`.
