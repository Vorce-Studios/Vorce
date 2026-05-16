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

## 2025-05-24 - DoS via Null-Pointer Dereference in MPV FFI

**Schwachstelle:** Beim Iterieren über die von MPV gelieferten Node-Maps (`crates/vorce-media/src/mpv_decoder.rs`) wurden C-Pointer (`keys[i]`) ohne Prüfung auf Null an `CStr::from_ptr` übergeben.
**Lektion:** FFI-Bibliotheken in C können bei internen Fehlern oder korruptem Input (wie hier manipulierten Video-Dateien) Null-Pointer zurückgeben. Die direkte Verwendung solcher Pointer in Rust's unsafe Blöcken führt zum sofortigen Absturz (Panic/DoS) und somit zu einem Stabilitäts- und Sicherheitsrisiko für das Gesamtsystem.
**Prävention:** Alle von FFI empfangenen raw Pointer müssen mit `.is_null()` geprüft werden, bevor sie dereferenziert oder an sichere Wrapper-Funktionen wie `CStr::from_ptr` weitergegeben werden.
