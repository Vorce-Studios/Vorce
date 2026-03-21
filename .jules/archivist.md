# 🗂️ Archivist's Journal

Kritische Erkenntnisse aus Repository-Verwaltungsaktivitäten.

---

## Eintragsformat

```
## YYYY-MM-DD - [Titel]
**Erkenntnis:** [Was gelernt]
**Aktion:** [Wie beim nächsten Mal anwenden].
```

---

## 2026-01-02 - Root Directory Cleanup

**Erkenntnis:** Das Root-Verzeichnis enthielt mehrere temporäre Dateien (`check_*.txt`, `test_results.txt`, `core_error.txt`) sowie falsch platzierte Dokumentation (`SECURITY.md`, `knowledge.md`) und redundante Dateien (`VERSION.txt`).

**Aktion:**
- `SECURITY.md` nach `.github/` verschoben.
- `knowledge.md` nach `.jules/` verschoben.
- Temporäre Dateien nach `.temp-archive/2026-01-02-*` archiviert.
- `VjMapper.code-workspace` archiviert (Legacy-Name, nicht erlaubt im Root).

**Zusatz:** Merge-Konflikte in `module.rs`, `main.rs`, `module_eval.rs` behoben (HEAD priorisiert). Syntaxfehler in `module_canvas.rs` korrigiert.

## 2025-01-19 - WGSL Shader Cleanup

**Erkenntnis:** `crates/mapmap-render/shaders/` enthielt 10 `.wgsl` Dateien, die gegen die Projektstruktur verstoßen, da alle Shader in `shaders/` liegen sollten. Dies führte zu einer Inkonsistenz in der Shader-Verwaltung.

**Aktion:**
- Alle `.wgsl` Dateien aus `crates/mapmap-render/shaders/` nach `shaders/` verschoben.
- `crates/mapmap-render/src/effect_chain_renderer.rs` aktualisiert, um die Shader aus dem neuen Pfad (`../../../shaders/`) zu laden.
- `crates/mapmap-render/shaders/` Verzeichnis gelöscht.
- Build mit `cargo check` verifiziert.

## 2026-01-29 - Repository Cleanup

**Erkenntnis:** `CODE-OF-CONDUCT.md` befand sich fälschlicherweise im Root. Das `.github/` Verzeichnis enthielt allgemeine technische und Jules-spezifische Dokumentation, die dort nicht hingehört. `.gitignore` fehlten einige Standard-Ausschlüsse.

**Aktion:**
- `CODE-OF-CONDUCT.md` nach `.github/` verschoben.
- Technische Dokumentation (`GMAIL_API_SETUP.md`, `README_CICD.md`, etc.) aus `.github/` nach `docs/08-TECHNICAL/` verschoben.
- Jules-Dokumentation (`JULES_INTEGRATION.md`, etc.) aus `.github/` nach `.jules/` verschoben.
- `.gitignore` aktualisiert (`.idea/`, `*.swo`, `.vscode/settings.json`, `.env`, `*.tmp`).

## 2026-01-31 - Patch Cleanup & Doc Organization

**Erkenntnis:** Das Root-Verzeichnis enthielt getrackte Patch-Dateien (`pr397.patch`, `pr398.patch`), die dort nicht hingehören. Zudem existierte ein nicht-konformes `docu/` Verzeichnis with Jules-spezifischen Notizen.

**Aktion:**
- `pr397.patch` and `pr398.patch` nach `.temp-archive/2026-01-31-*` archiviert and via `git rm` aus dem Repository entfernt.
- `docu/jules_gpu_ui.md` and `docu/jules_hw_accel.md` nach `.jules/` verschoben.
- `docu/` Verzeichnis entfernt.

## 2026-02-06 - Repository Cleanup & DLL Relocation

**Erkenntnis:** Das Root-Verzeichnis enthielt nicht erlaubt dem DLL-Dateien (FFmpeg Abhängigkeiten) and eine Patch-Datei (`pr398.patch`), was gegen die Repository-Richtlinien verstößt. Zudem lag `copy_ffmpeg_dlls.bat` im Root statt im `scripts/` Verzeichnis.

**Aktion:**
- DLLs (`avcodec-61.dll`, etc.) and `pr398.patch` nach `.temp-archive/2026-02-06-*` archiviert.
- `tmp/fix_player.ps1` nach `.temp-archive/` verschoben und `tmp/` entfernt.
- `copy_ffmpeg_dlls.bat` nach `scripts/` verschoben und Pfade korrigiert (`%~dp0..\`).

## 2026-02-09 - Archive Maintenance

...

## 2026-03-12 - Root Directory Cleanup

**Erkenntnis:** Es wurden MapFlow-Log-Dateien (`mapflow.log.*`) im Verzeichnis `scripts/archive/logs/` gefunden, welche fälschlicherweise in Git verfolgt wurden, da die aktuelle `.gitignore`-Regel (`/logs/` und `*.log`) das Datums-Suffix nicht erfasste.
**Aktion:** Log-Dateien aus Git mit `git rm` entfernt und `.gitignore` aktualisiert (`scripts/archive/logs/`), um zukünftige Verfolgung von diesen Dateien zu verhindern.

## 2026-03-02 - Temporäre Dateien im Root verschoben
**Erkenntnis:** Im Root-Verzeichnis befanden sich temporäre Entwicklungsskripte und Patches (`fix_bevy_test.py`, `fix_script.py`, `patch.diff`, `test_script.py`), die nicht den Projektstandards für Root-Dateien entsprechen und unnötig mit Git getrackt wurden.
**Aktion:** Dateien via `git rm --cached` aus Git entfernt und mit Datum-Präfix ins `.temp-archive/` verschoben.

## 2026-03-19 - Patch Cleanup
**Erkenntnis:** Das Root-Verzeichnis enthielt eine getrackte Patch-Datei (`patch.diff`), die dort nicht hingehört.
**Aktion:** `patch.diff` nach `.temp-archive/2026-03-19-patch.diff` archiviert und via `git rm` aus dem Repository entfernt.

## 2026-03-19 - Vcpkg JSON Cleanup
**Erkenntnis:** Das Root-Verzeichnis enthielt eine `vcpkg.json`, die typischerweise im Projekt-Root toleriert wird (C++ Dependency-Management), jedoch laut Regeln zur Prüfung gemeldet wurde. Da es im Standard-Kontext erlaubt sein könnte, wurde entschieden, die Datei dort zu belassen, aber im Journal als geprüft zu vermerken.
**Aktion:** `vcpkg.json` verifiziert. Keine Aktion erforderlich.

## 2026-03-19 - CI Failure Analysis
**Erkenntnis:** Ein Test in mapmap-bevy schlug in der CI fehl (`headless_runner_disables_embedded_host_plugins`), da ihm das `#[ignore]` Tag für GPU-Tests fehlte. Des Weiteren gab es diverse `cargo fmt` Fehlschläge im Code.
**Aktion:** Der Test wurde gemäß den Repository-Regeln (AGENTS.md) mit `#[ignore]` markiert, da Render/GPU-Tests ohne interaktive GUI-Umgebung auf CI nicht laufen. Außerdem wurde `cargo fmt` global ausgeführt, um Formatierungswarnungen zu beheben.
