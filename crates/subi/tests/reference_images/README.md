# Visual Reference Images

Diese PNG-Dateien sind die Referenzbilder fuer die lokalen visuellen Regressionstests in
`crates/subi/tests/visual_capture_tests.rs`.

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
cargo run -p subi --bin subi_visual_harness --no-default-features -- reference --scenario checkerboard --output crates/subi/tests/reference_images/checkerboard.png
cargo run -p subi --bin subi_visual_harness --no-default-features -- reference --scenario alpha_overlay --output crates/subi/tests/reference_images/alpha_overlay.png
cargo run -p subi --bin subi_visual_harness --no-default-features -- reference --scenario gradient --output crates/subi/tests/reference_images/gradient.png
```

## Lokale visuelle Tests ausfuehren

```powershell
$env:SUBI_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"
cargo test -p subi --no-default-features --test visual_capture_tests -- --ignored --nocapture
```

Wenn `SUBI_VISUAL_CAPTURE_OUTPUT_DIR` nicht gesetzt ist, landen die Screenshots in einem
temporaeren Ordner unter `%TEMP%`.

Relative Pfade in `SUBI_VISUAL_CAPTURE_OUTPUT_DIR` werden gegen die Repo-Wurzel aufgeloest.
