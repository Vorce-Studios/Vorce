# Visual Reference Images & Release Smoke Baseline

Diese PNG-Dateien sind die Referenzbilder fuer die lokalen visuellen Regressionstests in
`crates/vorce/tests/visual_capture_tests.rs`.

Zusaetzlich beschreibt diese Readme die aktuelle Baseline fuer den App-weiten Release-Smoke-Test.

## Release-Smoke Automation Path

Der minimale end-to-end Release-Smoke-Test existiert in `crates/vorce/tests/app_automation_tests.rs` (insbesondere `test_release_smoke_automation_empty_project`).

Dieser Test startet den echten Vorce-App-Build (`Vorce.exe`) im `--mode automation` und exportiert nach einer definierten Anzahl Frames automatisiert einen GUI-Screenshot.

### Lokaler Aufruf der Automation-Smoke-Tests

Da dieser Test ein sichtbares winit/wgpu-Fenster erfordert, benoetigt er eine **lokale interaktive Windows GPU/Desktop Session**.

```powershell
cargo build --release -p vorce --bin Vorce
cargo test -p vorce --test app_automation_tests -- --ignored --nocapture
```

Die Screenshots aus diesem Test landen im Ordner `target/automation_test_output`.

### Abgrenzung zu Output/Projector QA
Der Automation-Smoke-Test und der Visual-Harness sind fokussiert auf die **Baseline-Smoke-Coverage**:
- Pruefung, ob die App ohne Crash startet
- Validierung des elementaren Main-Window Renderings (winit + wgpu)
- Pruefung des Readback/Screenshot-Mechanismus selbst

Ein volles Multi-Output-Setup (z.B. reale zweite Monitore, Masken auf Projektoren) ist explizit **nicht Scope** dieses Basistests, sondern wird in breiteren Projector-QA-Matrizen behandelt.

## Visual Harness & Reference Image Workflow

Der Harness (`crates/vorce/src/bin/vorce_visual_harness/main.rs`) dient als minimalistischer, deterministischer Test-Wrapper fuer die GPU-Surface-Praesentation.

### Erste Szenarien

- `checkerboard.png`
  - prueft Orientierung, UV-Flip, Farbkanalvertauschungen und harte Kanten auf einer echten Surface
- `alpha_overlay.png`
  - prueft transparentes Rendering und Alpha-Blending in einem sichtbaren Fenster
- `gradient.png`
  - prueft weiche Farbverlaeufe, Capture-Readback und zentrale Markierungen

Diese drei Faelle liefern mehr Signal als reine Logik- oder offscreen-Tests, weil sie den echten
Fenster-, Swapchain-, Present- und Screenshot-Pfad verwenden.

### Referenzbilder neu erzeugen

Die Neuerstellung benoetigt ebenfalls eine aktive, interaktive Windows-Sitzung.

Von der Repo-Wurzel aus:

```powershell
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario checkerboard --output crates/vorce/tests/reference_images/checkerboard.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario alpha_overlay --output crates/vorce/tests/reference_images/alpha_overlay.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario gradient --output crates/vorce/tests/reference_images/gradient.png
```

### Lokale visuelle Tests ausfuehren

Benoetigt eine interaktive Desktop-Session.

```powershell
$env:VORCE_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"
cargo test -p vorce --no-default-features --test visual_capture_tests -- --ignored --nocapture
```

Wenn `VORCE_VISUAL_CAPTURE_OUTPUT_DIR` nicht gesetzt ist, landen die Screenshots in einem
temporaeren Ordner unter `%TEMP%`.

Relative Pfade in `VORCE_VISUAL_CAPTURE_OUTPUT_DIR` werden gegen die Repo-Wurzel aufgeloest.

## Non-Interactive CI Gap
Aktuell fehlen uns vollwertige Mock-Surfaces oder virtuelle GPU-Driver im CI, weshalb diese grafischen Tests in der Standard-CI (Linux headless oder standard Windows GitHub Runner) nicht stabil durchlaufen wuerden.

Aus diesem Grund sind `app_automation_tests` und `visual_capture_tests` aktuell mit `#[ignore]` markiert und erfordern lokale, interaktive GPU-Sessions oder spezialisierte Self-Hosted Runner mit echten Displays.
