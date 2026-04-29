## 2025-05-24 - DoS via Option::unwrap() in ffmpeg scaler

**Schwachstelle:** Ein `unwrap()` Aufruf befand sich im Media-Decoder (`crates/vorce-media/src/decoder.rs` auf Zeile 430), wenn die gecachte Skalierungsvariable (`SCALER_CACHE`) zurückgegeben wurde.

**Lektion:** Falls das Neu-Anlegen des FFmpeg-Scalers fehlschlägt, aber das Error-Handling oder der Status des Objektes nicht sicher abgefangen wird, führt dies zu einem direkten Absturz durch Panic (Denial of Service).

**Prävention:** Optionen und Caches sollten immer mit Pattern Matching oder `if let Some()` / `let Some() = else {}` sicher aufgelöst werden. Wenn der Zustand ungültig ist, sollte ein sauber gekapselter Fehlerwert (wie `MediaError::DecoderError`) zurückgeliefert werden.
## 2024-05-18 - [NDI Receiver Thread Panic] **Schwachstelle:** format_clone.lock().unwrap() im NDI-Receiver Thread führt zum Absturz des Netzwerk-Threads bei einem PoisonError. **Lektion:** Mutex-Poisoning bei asynchronen Netzwerk/Media-Threads kann Folge-Abstürze provozieren (DoS auf den Video-Stream). **Prävention:** PoisonError explizit mit match oder unwrap_or_else abfangen, um robuste Fehlererholung zu ermöglichen.
