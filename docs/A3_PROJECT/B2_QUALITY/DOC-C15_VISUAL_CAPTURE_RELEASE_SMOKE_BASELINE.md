# Visual Capture Release Smoke Baseline

**Datum:** 2026-03-29
**Kontext:** Issue #77 / Part of Vorce#122
**Phase:** 7 - Release Readiness

Dieses Dokument definiert die minimale Baseline für visuelle Smoke-Tests und grafische Regressionen im aktuellen Vorce-Repository. Es formalisiert den bestehenden, interaktiven Capture-Pfad als offizielle Grundlage für Release-Qualifikationen.

---

## 1. Minimaler Release-Smoke-Pfad (Automation Screenshot)

Der primäre end-to-end Smoke-Test für den App-Lifecycle und das Rendering ist in `crates/vorce/tests/app_automation_tests.rs` als `test_release_smoke_automation_empty_project` implementiert.

### Ziel
Verifikation, dass die Anwendung komplett starten, den Rendering-Pipeline-Setup abschließen, einen Frame ausliefern und sauber beenden kann. Dieser Test nutzt den echten App-Pfad (`--mode automation`).

### Durchführung
```powershell
# Baut Vorce im Release-Modus (Empfohlen für echte Laufzeitbedingungen)
cargo build --release --bin Vorce

# Führt den Automations-Test aus
cargo test -p vorce --test app_automation_tests -- --ignored
```
*Anmerkung: Der Test ruft intern das Vorce Binary auf mit `--mode automation`, lädt ein leeres Projekt, rendert 10 Frames und speichert einen Screenshot.*

### Akzeptanzkriterien
*   Das Binary startet fehlerfrei.
*   Es erfolgt kein Crash während der Initialisierung.
*   Ein Screenshot `automation_frame_10.png` in der korrekten Auflösung (1280x720) wird im Ausgabeverzeichnis (`target/automation_test_output`) abgelegt.

---

## 2. Der Harness-basierte Capture-Pfad (Visuelle Regression)

Für dedizierte Pixel-Regressionstests wird das isolierte Binary `vorce_visual_harness` verwendet. Die Tests liegen in `crates/vorce/tests/visual_capture_tests.rs` und referenzieren Bilder in `crates/vorce/tests/reference_images/`.

### Ziel
Prüfung elementarer Rendering-Fähigkeiten (Orientierung, Alpha-Blending, Farbverläufe) ohne den Overhead der kompletten App-Logik, aber unter Nutzung der echten WGPU-Surface.

### Durchführung
```powershell
# Setzt das Ausgabeverzeichnis (Optional, sonst %TEMP%)
$env:VORCE_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"

# Führt die visuellen Regressionstests aus
cargo test -p vorce --test visual_capture_tests -- --ignored
```

Dieser Harness testet aktuell drei Basis-Szenarien:
*   `checkerboard`: Hard-Edge Rendering und Orientierung.
*   `alpha_overlay`: Transparentes Blending.
*   `gradient`: Weiche Verläufe und Interpolation.

Weitere Details und Anweisungen zur Neugenerierung der Referenzbilder finden sich in `crates/vorce/tests/reference_images/README.md`.

---

## 3. Explizite Umgebungsvoraussetzungen (Runner/Session)

**WICHTIG:** Aktuell existiert *kein* vollständig non-interaktiver, "Headless"-Modus, der die WGPU-Surface-Präsentation verlässlich mockt. Beide Capture-Pfade benötigen echte Display-Capabilities.

Um die Tests (die standardmäßig mit `#[ignore]` markiert sind) erfolgreich auszuführen, **muss** die Umgebung folgende Bedingungen erfüllen:

1.  **Aktive Windows-Sitzung:** Der Runner muss in einer interaktiven Desktop-Session (mit GUI) laufen, nicht als isolierter Hintergrunddienst ohne Session 0 Zugang.
2.  **GPU Vorhanden:** Eine physische oder voll virtualisierte GPU, die Vulkan/DX12 via WGPU unterstützt, ist zwingend.
3.  **Kein Screen-Lock:** Der Bildschirm darf nicht gesperrt sein, und der Rechner darf sich nicht im Sleep-Modus befinden.

Diese Einschränkung (Gap) wird bis auf Weiteres akzeptiert. Headless CI-Umgebungen (z. B. Standard GitHub Actions Linux Runner ohne Xvfb/GPU) *können diese Tests nicht ausführen*.

---

## 4. Abgrenzung zur Output-/Projector-QA

Diese Baseline-Tests decken den *Basis-Start* und das *grundlegende Rendering in ein Surface* ab.

**Nicht Teil dieser Smoke-Baseline ist:**
*   Das Testen von echtem Multi-Output-Verhalten (mehrere physische Monitore).
*   Testen von Keystone, Edge-Blending oder Maskierung auf spezifischen Projektor-Outputs.
*   Das Starten und Validieren von Legacy-Netzwerk-Outputs (NDI, SRT).

Diese erweiterten Aspekte sind explizit Bestandteil der Output-Matrix (siehe Vorce#49 und Vorce#1095) und bedürfen entweder spezifischerer Hardware-Setups oder dedizierter, isolierter Tests. Diese Baseline stellt sicher, dass der Weg *bis* zum finalen Output grundsätzlich funktioniert, prüft aber nicht jede Abzweigung.
