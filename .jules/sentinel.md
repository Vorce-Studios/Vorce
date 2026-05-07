## 2025-05-24 - DoS via Option::unwrap() in ffmpeg scaler

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im Media-Decoder (`crates/vorce-media/src/decoder.rs` auf Zeile 430), wenn die gecachte Skalierungsvariable (`SCALER_CACHE`) zurückgegeben wurde.

**Lektion:** Falls das Neu-Anlegen des FFmpeg-Scalers fehlschlägt, aber das Error-Handling oder der Status des Objektes nicht sicher abgefangen wird, führt dies zu einem direkten Absturz durch Panic (Denial of Service).

**Prävention:** Optionen und Caches sollten immer mit Pattern Matching oder `if let Some()` / `let Some() = else {}` sicher aufgelöst werden. Wenn der Zustand ungültig ist, sollte ein sauber gekapselter Fehlerwert (wie `MediaError::DecoderError`) zurückgeliefert werden.


## 2025-05-24 - DoS via Option::unwrap() in ping-pong buffer

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich in der `apply()` Funktion des Effect Chain Renderers (`crates/vorce-render/src/effect_chain_renderer/apply.rs`), wenn auf den Ping-Pong-Buffer zugegriffen wurde.
**Lektion:** Wenn `self.ping_pong` aufgrund von Fehlern im Backend (z. B. Out-of-Memory oder invaliden Größen) auf `None` bleibt, führt die Ausführung der Render-Pipeline zum sofortigen Absturz (DoS).
**Prävention:** Bei kritischen Render-Pfaden müssen Resourcen sicher mit `if let Some()` oder pattern matching entpackt werden. Schlägt dies fehl, kann der Render-Pass sicher übersprungen oder mit einer Warnung abgebrochen werden, ohne die gesamte Applikation zum Absturz zu bringen.

## 2025-05-24 - [CRITICAL] Overly Permissive CORS Policy

**Schwachstelle:** Die CORS-Konfiguration erlaubte explizit den Wildcard-Origin `*` (`tower_http::cors::Any`), wenn dieser in der Konfiguration vorhanden war. Dies ermöglichte es beliebigen Webseiten, Anfragen an die Control-API zu stellen.

**Lektion:** CORS-Policies sollten niemals standardmäßig oder durch einfache Konfiguration Wildcards erlauben, insbesondere bei APIs, die sensitive Aktionen ausführen können.

**Prävention:** Wildcards in CORS-Einstellungen sollten im Code explizit abgefangen und ignoriert werden. Erlaubte Origins müssen als spezifische, vertrauenswürdige Domains konfiguriert werden.

## 2025-05-24 - DoS via Option::unwrap() in mpv_decoder

**Schwachstelle:** Zwei `unwrap()` Aufrufe befanden sich im Media-Decoder (`crates/vorce-media/src/mpv_decoder.rs` auf Zeilen 88 und 89) bei der Erstellung von `CString` aus String-Literalen.

**Lektion:** Obwohl die verwendeten String-Literale keine Null-Bytes enthalten und die Aufrufe in der Praxis sicher sind, kann ein versehentliches Ändern oder dynamisches Erzeugen dieser Strings ohne Null-Prüfung zu Paniken und damit zum Absturz der gesamten Anwendung führen.

**Prävention:** Verwende stattdessen sauberes Error Handling und fange Fehler elegant ab, z.B. durch `map_err`, das zu einem `MediaError::DecoderError` aufgelöst wird.
## 2026-05-07 - [CRITICAL] Fix Null Pointer Dereference in Media Decoder FFI
**Schwachstelle:** In `vorce-media/src/decoder.rs` wurde beim Kopieren von Hardware-beschleunigten Video-Frames (D3D11) der Pointer des decodierten Frames (`decoded.as_ptr()`) in einem unsafe-Block verwendet, ohne vorher auf Null zu prüfen. Dies hätte bei einem Fehler in FFmpeg zu einem Absturz der gesamten Applikation (Null Pointer Dereference) geführt.
**Lektion:** Pointers aus C-FFI-Aufrufen (wie hier von `ffmpeg-next`) können unter unerwarteten Bedingungen Null sein, besonders bei fehlerhaften Input-Dateien oder wenn die Hardware-Beschleunigung fehlschlägt.
**Prävention:** Vor jedem `unsafe`-Block, der C-Pointers dereferenziert, sollte stets eine explizite Überprüfung mit `.is_null()` erfolgen, um Fehler sicher in Rust-Ergebnisse (`Result::Err`) umzuwandeln und so einen kontrollierten Abbruch des Decodierungs-Frames zu gewährleisten.
