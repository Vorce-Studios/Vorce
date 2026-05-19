## 2024-05-24 - DoS via Option::unwrap() in codegen.rs

**Schwachstelle:** `generate_code` in `crates/vorce-core/src/codegen.rs` hat `Option` Typen mit `unwrap()` aufgelÃ¶st, ohne sicherzustellen, dass diese Werte immer vorhanden sind.

**Lektion:** Obwohl die verwendeten String-Literale keine Null-Bytes enthalten und die Aufrufe in der Praxis sicher sind, kann ein versehentliches Ã„ndern oder dynamisches Erzeugen dieser Strings ohne Null-PrÃ¼fung zu Paniken und damit zum Absturz der gesamten Anwendung fÃ¼hren.

**PrÃ¤vention:** Use sauberes Error Handling und fange Fehler elegant ab, z.B. durch `map_err`, das zu einem `MediaError::DecoderError` aufgelÃ¶st wird.

## 2025-05-24 - DoS via Option::unwrap() in mpv_decoder

**Schwachstelle:** In `vorce-media/src/decoder.rs` wurde die Funktion `CStr::from_ptr(cstr).to_str().unwrap()` verwendet, um C-Strings in Rust-Strings umzuwandeln.

**Lektion:** Obwohl die verwendeten String-Literale keine Null-Bytes enthalten und die Aufrufe in der Praxis sicher sind, kann ein versehentliches Ã„ndern oder dynamisches Erzeugen dieser Strings ohne Null-PrÃ¼fung zu Paniken und damit zum Absturz der gesamten Anwendung fÃ¼hren.

**Prävention:** Verwende stattdessen sauberes Error Handling und fange Fehler elegant ab, z.B. durch `map_err`, das zu einem `MediaError::DecoderError` aufgelöst wird.

## 2026-05-07 - [CRITICAL] Fix Null Pointer Dereference in Media Decoder FFI  
**Schwachstelle:** In `vorce-media/src/decoder.rs` wurde beim Kopieren von Hardware-beschleunigten Video-Frames (D3D11) der Pointer des decodierten Frames (`decoded.as_ptr()`) in einem unsafe-Block verwendet, ohne vorher auf Null zu prüfen. Dies hätte bei einem Fehler in FFmpeg zu einem Absturz der gesamten Applikation (Null Pointer Dereference) geführt.
**Lektion:** Pointers aus C-FFI-Aufrufen (wie hier von `ffmpeg-next`) können unter unerwarteten Bedingungen Null sein, besonders bei fehlerhaften Input-Dateien oder wenn die Hardware-Beschleunigung fehlschlägt.
**Prävention:** Vor jedem `unsafe`-Block, der C-Pointers dereferenziert, sollte stets eine explizite Überprüfung mit `.is_null()` erfolgen, um Fehler sicher in Rust-Ergebnisse (`Result::Err`) umzuwandeln und so einen kontrollierten Abbruch des Decodierungs-Frames zu gewährleisten.

## 2025-05-24 - DoS via Option::unwrap() in media_library.rs tests

**Schwachstelle:** In den Tests für die Media-Library wurde `unwrap()` auf Ergebnisse von Datenbankabfragen verwendet, was bei Inkonsistenzen in der Testdatenbank zu Paniken führte.

**Lektion:** Auch in Testcode sollte `unwrap()` sparsam eingesetzt werden, da Paniken in Tests oft schwerer zu debuggen sind als saubere Error-Assertions.

**PrÃ¤vention:** Nutze stattdessen die Features deines Testframeworks (wie `?` in Tests, die `Result` zurÃ¼ckgeben), um Fehler sauber zu propagieren.

## 2025-05-25 - [HIGH] Missing Error Propagation in Codegen

**Schwachstelle:** In `crates/vorce-core/src/codegen.rs` wurden Fehler bei der Dateioperation ignoriert, anstatt sie an den Aufrufer zurÃ¼ckzugeben.
**Lektion:** Stumme Fehler fÃ¼hren zu schwer zu debuggenden ZustÃ¤nden, in denen die Anwendung scheinbar funktioniert, aber keine Daten generiert werden.
**PrÃ¤vention:** Use `.map_err()` to propagate errors up the call stack, explicitly defining error types like `CodegenError` where appropriate.
## 2025-01-20 - [Denial of Service (DoS)] **Schwachstelle:** `expect()` calls exist in `vorce-media/src/pipeline.rs` and `vorce-render/src/mesh_buffer_cache.rs` and `vorce-render/src/texture.rs`. **Lektion:** Code relied on expect() which can panic and cause DoS. **Prävention:** Use safe error handling or fallback defaults.

## 2025-05-24 - [HIGH] Path Traversal in Project Loader

**Schwachstelle:** `load_project` in `crates/vorce-io/src/project.rs` hat Dateipfade nicht auf `..` Komponenten validiert, wodurch Path Traversal beim Laden von Projekten mÃ¶glich war.
**Lektion:** Es fehlte eine Validierungsschicht zwischen externen Pfaden und dem Dateisystemzugriff.
**PrÃ¤vention:** Bei jeglichem Einlesen von Dateien über externe oder dynamische Pfade muss vor dem Aufruf von `File::open` oder `fs::read` zwingend eine Validierung der Pfadkomponenten stattfinden, idealerweise durch den Ausschluss von `Component::ParentDir` oder eine strikte Sandboxing-Architektur.

## 2025-05-24 - [Sicherheitsverbesserung] Fix UI Hold Button panic
**Schwachstelle:** Ein `unwrap()` Aufruf befand sich in der `check_hold_state` Funktion (`crates/vorce-ui/src/widgets/custom/safety.rs`), um die vergangene Zeit zu berechnen.
**Lektion:** Auch wenn die Variable kurz zuvor auf `None` geprüft wird, kann es in komplexen UI-Zuständen zu Race-Conditions oder unerwartetem Verhalten kommen, was durch `unwrap()` zum Absturz führt.
**Prävention:** Optionen stets sicher mit `if let Some()` auflösen und einen Default-Wert verwenden, falls die Ausführung fehlschlägt, anstatt die gesamte Applikation durch Panic abstürzen zu lassen.
## 2025-05-18 - Denial of Service durch fehlende NDI-Laufzeitumgebung **Schwachstelle:** `expect()` beim Erstellen des `NdiReceiver` in `UIAction::ConnectNdiSource` in `crates/vorce/src/app/actions/module.rs`. Wenn NDI nicht verfügbar war, crashte die gesamte Applikation bei der Zuweisung einer Quelle. **Lektion:** Konstruktoren für externe Abhängigkeiten wie I/O-Module können fehlschlagen und dürfen in der App-Schleife nicht mit `unwrap()` oder `expect()` erzwungen werden. **Prävention:** Konsequente Nutzung von Fehlerbehandlung (`match` oder `?`) bei der Instanziierung von I/O-Receivern, ergänzt durch Logging, anstatt Panics auszulösen.
