## 🛡️ Sicherheits-Update

**🚨 Schweregrad:** CRITICAL/HIGH
**💡 Schwachstelle:** Path Traversal in MediaLoaders. Die Decoder (`StillImageDecoder`, `GifDecoder`, `MpvDecoder`, `FFmpegDecoder`, `ImageSequenceDecoder`) in `vorce-media` luden Dateien, ohne die Existenz von `..` (Parent Directory) Komponenten zu validieren, was das Lesen arbiträrer Dateien über manipulierte Pfade ermöglichen könnte.
**🎯 Impact:** Auslesen von Systemdateien ausserhalb des Projektordners.
**🔧 Fix:** `std::path::Component::ParentDir` Check vor dem `File::open` oder Decoder-Aufruf hinzugefügt.
**✅ Verifikation:** `cargo check -p vorce-media` und `cargo test -p vorce-media` laufen fehlerfrei durch. Die Pfade werden nun sicher gefiltert.

## Verlinktes Issue
Fixes #0
