## 2025-05-24 - DoS via Option::unwrap() in ffmpeg scaler

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im Media-Decoder (`crates/vorce-media/src/decoder.rs` auf Zeile 430), wenn die gecachte Skalierungsvariable (`SCALER_CACHE`) zurückgegeben wurde.

**Lektion:** Falls das Neu-Anlegen des FFmpeg-Scalers fehlschlägt, aber das Error-Handling oder der Status des Objektes nicht sicher abgefangen wird, führt dies zu einem direkten Absturz durch Panic (Denial of Service).

**Prävention:** Optionen und Caches sollten immer mit Pattern Matching oder `if let Some()` / `let Some() = else {}` sicher aufgelöst werden. Wenn der Zustand ungültig ist, sollte ein sauber gekapselter Fehlerwert (wie `MediaError::DecoderError`) zurückgeliefert werden.

## 2026-04-25 - DoS via Option::unwrap() in EffectChainRenderer
**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im `EffectChainRenderer` (`crates/vorce-render/src/effect_chain_renderer/apply.rs` auf Zeilen 309 und 338), beim Zugriff auf den `ping_pong` Puffer.
**Lektion:** Falls der `ping_pong` Puffer aus irgendeinem Grund zur Laufzeit fehlt, führt dies zu einem direkten Absturz durch Panic (Denial of Service) beim Rendering.
**Prävention:** Caches oder Buffer, die lazy erzeugt werden (wie Option<PingPongBuffer>), sollten immer mit `if let Some()` oder `let Some() = ... else { return; }` sicher aufgelöst werden, statt mit `unwrap()`.
