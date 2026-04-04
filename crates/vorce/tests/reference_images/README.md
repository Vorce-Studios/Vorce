# Visual Reference Images

Diese PNG-Dateien sind die Referenzbilder fuer die lokalen visuellen Regressionstests in
`crates/vorce/tests/visual_capture_tests.rs`.

## Erste Szenarien

- `checkerboard.png`
  - prueft Orientierung, UV-Flip, Farbkanalvertauschungen und harte Kanten auf einer echten Surface
- `alpha_overlay.png`
  - prueft transparentes Rendering und Alpha-Blending in einem sichtbaren Fenster
- `gradient.png`
  - prueft weiche Farbverlaeufe, Capture-Readback und zentrale Markierungen

Diese drei Faelle liefern mehr Signal als reine Logik- oder offscreen-Tests, weil sie den echten
Fenster-, Swapchain-, Present- und Screenshot-Pfad verwenden.

## Referenzbilder neu erzeugen

Von der Repo-Wurzel aus:

```powershell
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario checkerboard --output crates/vorce/tests/reference_images/checkerboard.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario alpha_overlay --output crates/vorce/tests/reference_images/alpha_overlay.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario gradient --output crates/vorce/tests/reference_images/gradient.png
```

## Lokale visuelle Tests ausfuehren

```powershell
$env:VORCE_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"
cargo test -p vorce --no-default-features --test visual_capture_tests -- --ignored --nocapture
```

Wenn `VORCE_VISUAL_CAPTURE_OUTPUT_DIR` nicht gesetzt ist, landen die Screenshots in einem
temporaeren Ordner unter `%TEMP%`.

Relative Pfade in `VORCE_VISUAL_CAPTURE_OUTPUT_DIR` werden gegen die Repo-Wurzel aufgeloest.

## Automation Screenshot Baseline

Der aktuelle Haupt-Release-Smoke-Pfad für Visual Capture (Automation Screenshots) wird über den `--mode automation` Schalter der `Vorce`-Anwendung gesteuert.

Der Test `test_release_smoke_automation_empty_project` in `crates/vorce/tests/app_automation_tests.rs` stellt die minimale Automation-Screenshot-Baseline dar.

**Ausführung lokal:**

```powershell
cargo build --bin Vorce --release
cargo test -p vorce --test app_automation_tests -- --ignored --nocapture
```

Alternativ direkter Aufruf (als Beispiel):

```powershell
cargo run --bin Vorce --release -- --mode automation --fixture ./tests/fixtures/empty_project.vorce --exit-after-frames 10 --screenshot-dir ./target/automation_test_output
```

Dies generiert z.B. das Bild `automation_frame_10.png` in `target/automation_test_output/`.

### Runner / Session / Environment Prerequisites

Damit diese Tests erfolgreich laufen (sowohl `Vorce_visual_harness` Capture als auch der Automation Smoke Test), gelten strikte Voraussetzungen an die Laufzeitumgebung:

- **Echte, interaktive GPU/Desktop-Session erforderlich:** Die Capture-Mechanik (wgpu Surface, winit Windows) setzt ein valides X11/Wayland (Linux) oder Desktop Window Manager (Windows) Environment voraus.
- Es muss eine Grafikkarte (GPU) vorhanden sein oder alternativ ein vollwertiger Software-Rasterizer aktiv sein, der Vulkan/DX12 emulieren kann.
- Headless-Umgebungen (wie Standard GitHub Actions Ubuntu Runner) schlagen hier mit OS-Errors (z.B. fehlendes Display oder verweigerte Window-Creation) fehl.
- Für Windows Runner: Session darf nicht gesperrt sein, Sleep muss deaktiviert sein, um `Occluded` / `Lost` Surface Fehler zu vermeiden.

### Gap Documentation: Headless CI

Es existiert aktuell **kein** vollständig "non-interactive" / Headless CI Pfad für App-Level-Visual-Regression-Tests, der ohne valides Display-Environment auskommt.
Das bedeutet: Wenn kein lokaler Display-Manager verfügbar ist, werden Automation-Visual-Tests fehlschlagen. Wir nutzen bewusst `#[ignore]` für diese Tests in normalen CI-Läufen und lagern sie an Self-Hosted-Runner mit aktiver GUI-Sitzung aus, solange der Render-Pfad für Tests nicht komplett Offscreen und OS-Mock-Fähig abstrahiert ist. Diese Lücke wird explizit akzeptiert, um reale Produktionsbedingungen (winit, echte Swaps) abzutesten.

### Beziehung zur Projector/Output QA

Diese Automation Smoke Baseline deckt primär den Main-Window-Startzustand und elementare Rendervorgänge ab (Release-Smoke). Sie stellt sicher, dass die Anwendung im Kern GUI- und Render-fähig ist.

Sie ist **nicht** verantwortlich für die detaillierte Evaluierung spezifischer Multi-Projektor-Setups, Maskierungen, Warping, oder komplexe Output-Routing Topologien. Erweiterte Matrix-Tests für Projektoren fallen in den separaten Scope von `Vorce-Studios/Vorce#49` (Multi-Output / Projector-QA) und sollten nicht mit den Kern-Automations-Regressionen vermischt werden.
