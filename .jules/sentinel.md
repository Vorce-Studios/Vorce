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
## 2025-05-18 - Denial of Service durch fehlende NDI-Laufzeitumgebung **Schwachstelle:** `expect()` beim Erstellen des `NdiReceiver` in `UIAction::ConnectNdiSource` in `crates/vorce/src/app/actions/module.rs`. Wenn NDI nicht verfügbar war, crashte die gesamte Applikation bei der Zuweisung einer Quelle. **Lektion:** Konstruktoren für externe Abhängigkeiten wie I/O-Module können fehlschlagen und dürfen in der App-Schleife nicht mit `unwrap()` oder `expect()` erzwungen werden. **Prävention:** Konsequente Nutzung von Fehlerbehandlung (`match` oder `?`) bei der Instanziierung von I/O-Receivern, ergänzt durch Logging, anstatt Panics auszulösen.
