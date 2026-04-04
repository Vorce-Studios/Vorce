# Visual Capture & Release Smoke Baseline

**Status:** Active
**Phase:** 7 - Release Readiness

This document formalizes the baseline for automated visual testing and release smoke testing within the current Vorce repository structure. It outlines the minimal smoke path utilizing the automation screenshot flow, details the harness-based capture workflow, specifies environmental prerequisites, and clarifies the separation between this baseline and broader output quality assurance.

## 1. Minimal Smoke Path (Automation Screenshot Flow)

The application E2E automation flow represents our minimal release-smoke testing baseline. It verifies that the core application and rendering systems initialize correctly, render frames, and successfully output capture artifacts without requiring manual interaction.

### E2E Automation Overview

- **Entry Point:** `crates/vorce/src/main.rs` (using `--mode automation`)
- **Test Implementation:** `test_release_smoke_automation_empty_project` located in `crates/vorce/tests/app_automation_tests.rs`.
- **Mechanism:** Vorce is launched with specific CLI arguments to load a fixture, run for a defined number of frames, capture a screenshot, and exit automatically.

### Running the Smoke Path Locally

To manually trigger the automation screenshot flow:

```powershell
cargo run --bin Vorce --release -- --mode automation --fixture ./tests/fixtures/empty_project.vorce --exit-after-frames 10 --screenshot-dir ./target/automation_test_output
```

**Artifact Path:** The resulting screenshot will be saved as `automation_frame_10.png` within the specified `--screenshot-dir`.

## 2. Visual Capture Harness Workflow

The visual capture harness focuses on isolating and testing specific rendering scenarios directly on a genuine GPU surface, comparing output against known reference images.

### Harness Overview

- **Entry Point:** `crates/vorce/src/bin/vorce_visual_harness/main.rs`
- **Test Implementation:** E.g., `checkerboard_matches_reference`, `alpha_overlay_matches_reference`, `gradient_matches_reference` located in `crates/vorce/tests/visual_capture_tests.rs`.
- **Reference Images:** Stored in `crates/vorce/tests/reference_images/` (documented in `README.md` in that same directory).
- **Mechanism:** Compares actual captured pixel data from specific scenarios against established references within an allowable mismatch ratio.

### Running the Visual Capture Tests Locally

The visual capture tests are ignored by default. To run them:

```powershell
# Optional: Set a specific output directory, otherwise it defaults to a temporary folder
$env:VORCE_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"

cargo test -p vorce --no-default-features --test visual_capture_tests -- --ignored --nocapture
```

### Generating New Reference Images

If rendering behavior intentionally changes, update references via the harness:

```powershell
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario checkerboard --output crates/vorce/tests/reference_images/checkerboard.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario alpha_overlay --output crates/vorce/tests/reference_images/alpha_overlay.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario gradient --output crates/vorce/tests/reference_images/gradient.png
```

## 3. Environmental Prerequisites and Limitations

Visual regression testing in Vorce requires a physical desktop environment due to the reliance on `winit` windowing and genuine `wgpu` surface presentation.

- **Interactive Desktop Session Required:** A fully non-interactive/headless baseline is currently **unavailable**. Both the App Automation Tests and Visual Capture Tests rely on creating a visible window. They will fail with OS errors in headless sandbox environments or standard CI runners that lack a display server.
- **Self-Hosted Runner Requirements:** To execute these tests in CI, they must run on a self-hosted runner (typically Windows) configured with a valid GPU and an active interactive desktop session (sleep disabled, screen unlocked).
- **CI Activation:** The environment variable `VORCE_SELF_HOSTED_RUN_VISUAL_AUTOMATION=true` must be set for the CI pipeline to un-ignore and execute the visual tests.

## 4. Relationship to Multi-Projector Output QA

This visual capture baseline is intentionally distinct from the broader Multi-Projector Output QA (tracked in Issue #49).

- **Scope of This Baseline:** Ensures the core rendering loop, primary window initialization, and standard GPU readback mechanisms function correctly. It serves as a rapid "is the rendering engine fundamentally broken?" check.
- **Scope of Multi-Projector QA (#49):** Addresses complex routing, secondary/tertiary output windows, multi-monitor topology handling, and projector-specific transformations (warp/blend).

These domains are separated to prevent the fundamental release smoke test from becoming bottlenecked by the complexities of multi-display hardware emulation or extensive routing matrices.
