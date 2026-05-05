## 2025-05-24 - DoS via Option::unwrap() in ffmpeg scaler

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im Media-Decoder (`crates/vorce-media/src/decoder.rs` auf Zeile 430), wenn die gecachte Skalierungsvariable (`SCALER_CACHE`) zurückgegeben wurde.

**Lektion:** Falls das Neu-Anlegen des FFmpeg-Scalers fehlschlägt, aber das Error-Handling oder der Status des Objektes nicht sicher abgefangen wird, führt dies zu einem direkten Absturz durch Panic (Denial of Service).

**Prävention:** Optionen und Caches sollten immer mit Pattern Matching oder `if let Some()` / `let Some() = else {}` sicher aufgelöst werden. Wenn der Zustand ungültig ist, sollte ein sauber gekapselter Fehlerwert (wie `MediaError::DecoderError`) zurückgeliefert werden.

<<<<<<< HEAD
## 2025-05-24 - [CRITICAL] Overly Permissive CORS Policy

**Schwachstelle:** Die CORS-Konfiguration erlaubte explizit den Wildcard-Origin `*` (`tower_http::cors::Any`), wenn dieser in der Konfiguration vorhanden war. Dies ermöglichte es beliebigen Webseiten, Anfragen an die Control-API zu stellen.

**Lektion:** CORS-Policies sollten niemals standardmäßig oder durch einfache Konfiguration Wildcards erlauben, insbesondere bei APIs, die sensitive Aktionen ausführen können.

**Prävention:** Wildcards in CORS-Einstellungen sollten im Code explizit abgefangen und ignoriert werden. Erlaubte Origins müssen als spezifische, vertrauenswürdige Domains konfiguriert werden.

## 2025-05-24 - DoS via Option::expect() in NDI receiver

**Schwachstelle:** Ein `expect()` Aufruf befand sich im NDI Receiver (`crates/vorce/src/app/actions.rs` in `UIAction::ConnectNdiSource`), wenn das NDI Receiver-Objekt erstellt wurde.

**Lektion:** Falls das Neu-Anlegen des NDI-Receivers fehlschlägt (z.B. wegen fehlender Bibliotheken oder Ressourcen), stürzt die gesamte Anwendung durch Panic ab (Denial of Service), wenn nur ein neuer NDI-Stream verbunden werden soll.

**Prävention:** Das Erstellen von NDI-Ressourcen sollte immer über sichere `match` oder `if let` Pattern gelöst werden, und bei Fehlschlag stattdessen ein gracefully Error in die Logs geschrieben und die Aktion abgebrochen werden, ohne die Applikation abstürzen zu lassen.

## 2026-04-25 - DoS via Option::unwrap() in EffectChainRenderer
**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im `EffectChainRenderer` (`crates/vorce-render/src/effect_chain_renderer/apply.rs` auf Zeilen 309 und 338), beim Zugriff auf den `ping_pong` Puffer.
**Lektion:** Falls der `ping_pong` Puffer aus irgendeinem Grund zur Laufzeit fehlt, führt dies zu einem direkten Absturz durch Panic (Denial of Service) beim Rendering.
**Prävention:** Caches oder Buffer, die lazy erzeugt werden (wie Option<PingPongBuffer>), sollten immer mit `if let Some()` oder `let Some() = ... else { return; }` sicher aufgelöst werden, statt mit `unwrap()`.
