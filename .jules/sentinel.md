## 2025-05-18 - [Fix Wildcard CORS Policy] **Schwachstelle:** `tower_http::cors::Any` allowed a wildcard origin `*` bypassing strict CORS policies. **Lektion:** Insecure default wildcard handling in CORS allowed all origins to access endpoints when they shouldn`t have, which introduces a potential security risk in web endpoints handling control flow. **Prävention:** Use exact origin matching and strict filtering on `allowed_origins` during configuration load rather than relying on wildcard matching tools.

## 2024-05-18 - [NDI Receiver Thread Panic] **Schwachstelle:** format_clone.lock().unwrap() im NDI-Receiver Thread führt zum Absturz des Netzwerk-Threads bei einem PoisonError. **Lektion:** Mutex-Poisoning bei asynchronen Netzwerk/Media-Threads kann Folge-Abstürze provozieren (DoS auf den Video-Stream). **Prävention:** PoisonError explizit mit match oder unwrap_or_else abfangen, um robuste Fehlererholung zu ermöglichen.


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

## 2025-05-24 - Potential Null Pointer Dereference in HAP player

**Schwachstelle:** In `crates/vorce-media/src/hap_player.rs` wurde der von `ffmpeg_next::codec::Parameters::as_ptr()` zurückgegebene Rohzeiger ohne vorherige Null-Prüfung dereferenziert.

**Lektion:** Rohzeiger aus externen Bibliotheken (wie FFmpeg) müssen immer auf Null geprüft werden, bevor sie in einem `unsafe`-Block dereferenziert werden, um Abstürze oder undefiniertes Verhalten zu vermeiden.

**Prävention:** Vor dem Zugriff auf Felder eines durch einen Rohzeiger repräsentierten C-Structs muss eine explizite Prüfung mit `.is_null()` durchgeführt werden. Schlägt diese fehl, sollte der Fehler sauber über den Ergebnistyp (`Result`) zurückgegeben werden.
