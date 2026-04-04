# Visual Capture Release Smoke Baseline

Dieses Dokument beschreibt die Minimal-Baseline fuer visuelle Smoke-Tests und automatisierte Screenshot-Pfade in Vorce (Stand Maerz 2026). Es dokumentiert den aktuellen Stand des Harness-basierten Capture-Pfads und der Anwendungs-Automatisierung.

## 1. Visual Capture Harness

Der Visual Capture Harness ist ein dediziertes Binary, das verwendet wird, um lokale, visuelle Regressionstests gegen feste Referenzbilder auszufuehren. Es fokussiert sich auf den reinen GPU-Renderpfad, Swapchain, Present und GPU-Readback-Mechanismen, ohne den Overhead der kompletten Vorce-Applikation.

### Wichtige Pfade & Dateien

* **Harness Binary:** `crates/vorce/src/bin/vorce_visual_harness/main.rs`
* **Test Suite:** `crates/vorce/tests/visual_capture_tests.rs`
* **Referenzbilder:** `crates/vorce/tests/reference_images/` (inklusive `README.md` fuer Details)

### Ausfuehrung & Voraussetzungen

Da dieser Harness echte Fenster aufbaut, eine Swapchain nutzt und auf GPU-Surface-Praesentation angewiesen ist, **muss** die Ausfuehrung in einer interaktiven Windows-Desktop-Sitzung mit gueltiger GPU erfolgen.

Die Tests sind standardmaessig ignoriert (`#[ignore]`), um zu verhindern, dass sie in normalen Headless-CI-Umgebungen fehlschlagen.

**Lokale Testausfuehrung:**
```powershell
$env:VORCE_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"
cargo test -p vorce --no-default-features --test visual_capture_tests -- --ignored --nocapture
```

**Referenzbilder neu generieren:**
```powershell
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario checkerboard --output crates/vorce/tests/reference_images/checkerboard.png
```

---

## 2. Minimal Release-Smoke Path (App Automation)

Zusaetzlich zum isolierten Visual Harness verfuegt Vorce ueber einen End-to-End-Automationsmodus, der die gesamte Applikation startet, grundlegende Subsysteme umgeht (Audio, MIDI, Hue), einige Frames rendert und dann einen Screenshot vom Hauptfenster exportiert.

### Wichtige Pfade & Dateien

* **Test Suite:** `crates/vorce/tests/app_automation_tests.rs`
* **Zentraler Test:** `test_release_smoke_automation_empty_project`
* **Main App Start:** `crates/vorce/src/main.rs` (nutzt `--mode automation`)

### Ausfuehrung & Voraussetzungen

Auch dieser Test baut auf die volle Winit/Wgpu-Infrastruktur und benoetigt eine interaktive Windows-Desktop-Sitzung.

**Lokale Ausfuehrung via CLI:**
```powershell
cargo run --bin Vorce -- --mode automation --fixture ./tests/fixtures/empty_project.vorce --exit-after-frames 60 --screenshot-dir ./target/automation_test_output
```

**CI-Integration:**
Um diesen Test auf einem self-hosted Windows Runner auszufuehren, muss die Umgebungsvariable `VORCE_SELF_HOSTED_RUN_VISUAL_AUTOMATION` auf `true` gesetzt werden (wie in `scripts/build/self-hosted-post-merge.ps1`).

---

## 3. The Non-Interactive Gap (Headless CI Limitations)

Aktuell existiert **kein** vollstaendig non-interaktiver (headless) Baseline-Pfad, der ohne eine aktive Desktop-Sitzung funktioniert.
Jegliche visuelle Capture-Tests (sowohl Harness als auch Automation) failen in klassischen, reinen Hintergrund-CI-Jobs aufgrund fehlender Window-Manager-Rechte oder unzureichender GPU-Treiber-Zustaende.

Dieser "Gap" ist explizit dokumentiert: Wir setzen auf diesem Stand nicht voraus, dass `visual_capture_tests` oder `app_automation_tests` ohne Weiteres in Standard-GitHub-Actions-Ubuntu-Runnern ausgefuehrt werden koennen. Der Workaround ist die Auslagerung auf spezifische, interaktive Self-Hosted Runner.

---

## 4. Abgrenzung zur Output / Projector QA

Die hier definierte Baseline dient ausschliesslich dem **Smoke-Testing**. Das Ziel ist:
* Zu validieren, dass die App ueberhaupt startet und rendert.
* Zu pruefen, ob der grundlegende Output im Main-Window (und der GPU-Readback) grundsaetzlich intakt ist (Orientierung, einfache Shader).

**Explizit nicht im Scope** dieses Smoke-Pfads (und abgedeckt durch Issue #49 / Multi-Projector QA) sind:
* Komplexe Multi-Window-Setups (mehrere Projektoren).
* Edge-Blending, Keystone, Warping und Maskierung auf logischer Ebene.
* Color-Management und erweiterte Render-Features (Parity Work #57).

Diese erweiterten Projektor-Tests erfordern eine separate Matrix und tiefere Validierung, die den Scope eines minimalen Release-Smokes uebersteigen.
