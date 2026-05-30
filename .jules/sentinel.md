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

**Lektion:** CORS-Policies sollten niemals standardmÃ¤ÃŸig oder durch einfache Konfiguration Wildcards erlauben, insbesondere bei APIs, die sensitive Aktionen ausfÃ¼hren kÃ¶nnen.

**PrÃ¤vention:** Wildcards in CORS-Einstellungen sollten im Code explizit abgefangen und ignoriert werden. Erlaubte Origins mÃ¼ssen als spezifische, vertrüge Domains konfiguriert werden.

## 2025-05-24 - DoS via Option::unwrap() in mpv_decoder

**Schwachstelle:** Zwei `unwrap()` Aufrufe befanden sich im Media-Decoder (`crates/vorce-media/src/mpv_decoder.rs` auf Zeilen 88 und 89) bei der Erstellung von `CString` aus String-Literalen.

**Lektion:** Obwohl die verwendeten String-Literale keine Null-Bytes enthalten und die Aufrufe in der Praxis sicher sind, kann ein versehentliches Ã„ndern oder dynamisches Erzeugen dieser Strings ohne Null-PrÃ¼fung zu Paniken und damit zum Absturz der gesamten Anwendung fÃ¼hren.

**Prävention:** Verwende stattdessen sauberes Error Handling und fange Fehler elegant ab, z.B. durch `map_err`, das zu einem `MediaError::DecoderError` aufgelöst wird.

## 2026-05-07 - [CRITICAL] Fix Null Pointer Dereference in Media Decoder FFI
**Schwachstelle:** In `vorce-media/src/decoder.rs` wurde beim Kopieren von Hardware-beschleunigten Video-Frames (D3D11) der Pointer des decodierten Frames (`decoded.as_ptr()`) in einem unsafe-Block verwendet, ohne vorher auf Null zu prüfen. Dies hätte bei einem Fehler in FFmpeg zu einem Absturz der gesamten Applikation (Null Pointer Dereference) geführt.
**Lektion:** Pointers aus C-FFI-Aufrufen (wie hier von `ffmpeg-next`) können unter unerwarteten Bedingungen Null sein, besonders bei fehlerhaften Input-Dateien oder wenn die Hardware-Beschleunigung fehlschlägt.
**Prävention:** Vor jedem `unsafe`-Block, der C-Pointers dereferenziert, sollte stets eine explizite Überprüfung mit `.is_null()` erfolgen, um Fehler sicher in Rust-Ergebnisse (`Result::Err`) umzuwandeln und so einen kontrollierten Abbruch des Decodierungs-Frames zu gewährleisten.

## 2025-05-24 - DoS via Option::unwrap() in media_library.rs tests

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im `test_media_library_limit` Test in `crates/vorce-core/src/media_library.rs` beim Erstellen von Verzeichnissen und Dateien.

**Lektion:** Wenn Fehler beim Erstellen von Verzeichnissen oder Dateien durch unwrap() ignoriert werden, fÃ¼hrt dies zu einem direkten Absturz durch Panic. Auch in Tests ist es besser, Fehler sauber mit `Result` zurÃ¼ckzugeben.

**PrÃ¤vention:** Verwende `Result` in Test-Signaturen und `?` zur Propagierung von Dateisystem-Fehlern anstelle von `unwrap()`.

## 2025-02-27 - [Security] Defense-in-Depth against WGSL Codegen Panics
**Schwachstelle:** The WGSL codegen implementation heavily relied on `.expect()` and `.unwrap()` which would cause the application to panic if shader graphs encountered unexpected types, parsing errors, or validation issues.
**Lektion:** Robust error handling is crucial for operations dependent on user input and serialized project files to prevent denial-of-service vulnerabilities.
**PrÃ¤vention:** Use `.map_err()` to propagate errors up the call stack, explicitly defining error types like `CodegenError` where appropriate.
## 2025-01-20 - [Denial of Service (DoS)] **Schwachstelle:** `expect()` calls exist in `vorce-media/src/pipeline.rs` and `vorce-render/src/mesh_buffer_cache.rs` and `vorce-render/src/texture.rs`. **Lektion:** Code relied on expect() which can panic and cause DoS. **Prävention:** Use safe error handling or fallback defaults.

## 2025-05-24 - [Sicherheitsverbesserung] Fix UI Hold Button panic
**Schwachstelle:** Ein `unwrap()` Aufruf befand sich in der `check_hold_state` Funktion (`crates/vorce-ui/src/widgets/custom/safety.rs`), um die vergangene Zeit zu berechnen.
**Lektion:** Auch wenn die Variable kurz zuvor auf `None` geprüft wird, kann es in komplexen UI-Zuständen zu Race-Conditions oder unerwartetem Verhalten kommen, was durch `unwrap()` zum Absturz führt.
**Prävention:** Optionen stets sicher mit `if let Some()` auflösen und einen Default-Wert verwenden, falls die Ausführung fehlschlägt, anstatt die gesamte Applikation durch Panic abstürzen zu lassen.

## 2025-05-24 - DoS via unwrap()/expect() panics

**Schwachstelle:** Die Codebase enthielt diverse ungeschützte `unwrap()` und `expect()` Aufrufe in UI-Rendering-Logik (z.B. in `egui_node_editor`) sowie in Window-Management und I/O-Schichten (`vorce-ui`, `vorce-io`, `vorce`).
**Lektion:** Wenn diese fehlgeschlagenen Result- oder Option-Typen in Panics münden, kommt es zum kompletten Anwendungsabsturz (Denial of Service), selbst wenn es nur ein harmloser UI-Fehler oder eine fehlende Fensterinstanz ist.
**Prävention:** Verwenden von sicheren Alternativen wie `unwrap_or_else(|| panic!(...))` in Tests oder echtes Pattern-Matching im Produktivcode, um sicherzustellen, dass die Applikation robust bleibt und keine Linter-Warnungen im CI-Check auftreten.


## 2025-05-24 - [HIGH] Path Traversal in Project Loader

**Schwachstelle:** `load_project` in `crates/vorce-io/src/project.rs` hat Dateipfade nicht auf `..` Komponenten validiert, wodurch Path Traversal beim Laden von Projekten mÃ¶glich war.
**Lektion:** Es fehlte eine Validierungsschicht zwischen externen Pfaden und dem Dateisystemzugriff.
**PrÃ¤vention:** Bei jeglichem Einlesen von Dateien über externe oder dynamische Pfade muss vor dem Aufruf von `File::open` oder `fs::read` zwingend eine Validierung der Pfadkomponenten stattfinden, idealerweise durch den Ausschluss von `Component::ParentDir` oder eine strikte Sandboxing-Architektur.

## 2025-01-20 - [Fix: Defense-in-depth on OSC and Config deserialization] **Schwachstelle:** Panic possible due to `unwrap`/`expect` during OSC network parsing and config loading. **Lektion:** Never unwrap network inputs or untrusted file configs since it can cause DoS. **Prävention:** Use `match` to properly handle `Result` types for robust error handling.

## 2024-05-18 - [Path Traversal Bypass]
**Schwachstelle:** Path Traversal checks using `std::path::Component::ParentDir` were bypassed on non-Windows platforms when paths contained Windows-style separators (e.g. `..\..\evil.mapmap`).
**Lektion:** `std::path::Path` parsing behavior depends on the target OS. On Linux, `\` is a valid filename character, so `..\` is parsed as a single component name, not a directory traversal.
**Prävention:** Always normalize path separators (e.g., `.replace("\\", "/")`) before performing traversal checks across all OS targets.

## 2025-05-24 - Path Traversal Mitigation in Media Decoders
**Schwachstelle:** The media decoders in `vorce-media` (e.g., `StillImageDecoder`, `MpvDecoder`, `GifDecoder`, `ImageSequenceDecoder`, `RealFFmpegDecoder`) loaded files from disk without explicitly validating whether the given path contained parent directory traversal components (`..`).
**Lektion:** While some path traversal protections existed at higher levels (like the project loading and MCP tools), the media decoding layer itself remained unprotected, allowing potential arbitrary file reads if external input bypassed higher-level checks.
**Prävention:** Add a defense-in-depth validation check directly inside the `open()` methods of media decoders, rejecting any paths that contain `std::path::Component::ParentDir`.

## 2025-05-24 - DoS via unwrap() in NDI Render Loop

**Schwachstelle:** Zwei ungeschützte `unwrap()` Aufrufe beim Zugriff auf die `ndi_offscreen_textures` Map in der Rendering-Schicht (in `crates/vorce/src/app/loops/render/mod.rs`).

**Lektion:** Falls eine Textur im NDI-Renderpass nicht erfolgreich erzeugt oder eingefügt wurde (z.B. wegen Grafikspeichermangel), führt das direkte Auspacken mittels `unwrap()` zum Paniken des gesamten Render-Loops und damit zum App-Crash (Denial of Service).

**Prävention:** Auf Resourcen-Maps innerhalb kritischer Loops (wie `app.ndi_offscreen_textures.get()`) muss immer mit einem sicheren Pattern wie `if let Some()` oder `match` zugegriffen werden. Fehlt die Resource, ist es sicherer, das Rendern für den aktuellen Frame zu überspringen (`continue`), anstatt die Anwendung abstürzen zu lassen.
