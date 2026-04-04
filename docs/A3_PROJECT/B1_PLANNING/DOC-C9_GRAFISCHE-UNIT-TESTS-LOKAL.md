# Visual-Capture-Readiness fuer grafische Tests

Stand: 2026-04-04

## Ziel

Diese Notiz definiert die aktuelle Baseline fuer grafische Tests und Automation-Screenshots im `vorce`-Repository. Sie dokumentiert die vorhandenen Pfade (`vorce_visual_harness` und den Automation-Modus), deren Laufzeitvoraussetzungen und grenzt sie von breiteren Themen wie Multi-Projector-QA ab.

Das Zielbild ist ein definierter Release-Smoke-Test, der heute schon auf den verfuegbaren (interaktiven Windows-)Umgebungen lauffaehig ist, auch wenn eine vollstaendig offscreen/headless ausfuehrbare CI-Loesung noch aussteht.

## Aktueller Stand

Der Testbestand im Repository bietet derzeit zwei visuelle Test- und Capture-Pfade, die jedoch **beide** auf eine lokale, interaktive Windows-Desktop-Session (mit GPU/Surface-Support) angewiesen sind. Echtes Headless-Testing fuer sichtbare Fenster ist derzeit nicht implementiert (Gap-Analyse siehe unten).

### 1. Harness-Based Visual Capture (`vorce_visual_harness`)

Der lokale visuelle Regressionstestpfad laeuft ueber das dedizierte Binary `vorce_visual_harness`.
Dieser Mechanismus startet ein reduziertes Fenster, erzeugt WGPU-Render-Readbacks und vergleicht sie gegen statische Referenz-PNGs.

- **Quellcode:** `crates/vorce/src/bin/vorce_visual_harness/main.rs`
- **Tests:** `crates/vorce/tests/visual_capture_tests.rs`
- **Szenarien:** `checkerboard`, `gradient`, `alpha_overlay`
- **Referenz-Bilder:** `crates/vorce/tests/reference_images/README.md`

#### Referenzbilder neu erzeugen
```bash
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario checkerboard --output crates/vorce/tests/reference_images/checkerboard.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario alpha_overlay --output crates/vorce/tests/reference_images/alpha_overlay.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario gradient --output crates/vorce/tests/reference_images/gradient.png
```

#### Ausfuehrung des Harness-Tests
Da eine interaktive GPU-Sitzung benoetigt wird, sind diese Tests mit `#[ignore]` markiert.
```bash
$env:VORCE_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"
cargo test -p vorce --no-default-features --test visual_capture_tests -- --ignored --nocapture
```

### 2. E2E Automation Screenshot Path

Fuer die komplette Vorce-App existiert ein Automationsmodus (`--mode automation`), der Teile der Seiteneffekte (wie MIDI, Audio, Hue) umgeht, eine Fixture-Datei laedt und nach N Frames definiert beendet, wobei optional ein Screenshot des Main-Windows gespeichert wird.

- **Tests:** `crates/vorce/tests/app_automation_tests.rs` (Test: `test_release_smoke_automation_empty_project`)
- **Implementierung:** Automation Lifecycle in `crates/vorce/src/main.rs`
- **Fixture:** `tests/fixtures/empty_project.vorce`

Dieser Pfad erzeugt einen E2E-Screenshot aus dem echten `run_app`-Pfad der gesamten UI.

## Release-Smoke Baseline

Die minimale Release-Smoke Baseline fuer visuelle Capture-Tests wird durch den E2E-Automation-Test dargestellt. Dieser garantiert, dass die App vollstaendig hochfaehrt, grundlegendes GPU-Rendering funktioniert und der Window/Readback-Mechanismus intakt ist.

**Empfohlener Minimal-Smoke-Aufruf (Manuell oder auf Self-Hosted CI):**
```bash
cargo test -p vorce --test app_automation_tests -- --ignored --nocapture
```
Dieser Befehl:
1. Ruft das `Vorce.exe` (Release oder Debug) mit `--mode automation` auf.
2. Laedt das leere Testprojekt.
3. Rendert 10 Frames.
4. Exportiert einen Screenshot nach `target/automation_test_output/automation_frame_10.png`.
5. Verifiziert dessen Abmessungen (1280x720).

## Environment-Voraussetzungen & Gaps

### Die "Headless"-Luecke
Vorce benoetigt zwingend eine gueltige `wgpu::Surface` mit Present-Mode. Weder der Harness noch der Automation-Modus koennen aktuell "echt headless" (z. B. in einer typischen reinen Linux/Docker-CI ohne X11/Wayland oder in Windows ohne gueltige interaktive Sitzung) ausgefuehrt werden.

**Aktuelle Limitierungen:**
- Echte sichtbare GUI-Automation und Capture schlagen fehl, wenn der Runner als reiner Hintergrunddienst ausgefuehrt wird.
- Windows Lock-Screens brechen die `wgpu`-Surface-Konfiguration.

**Betriebsbedingungen fuer Runner:**
- Fuer CI/Automation-Laeufe: Der Windows-Runner MUSS interaktiv in einer angemeldeten Desktop-Sitzung laufen (Auto-Logon).
- Bildschirmsperre, Sleep und konkurrierende manuelle Nutzung muessen deaktiviert sein.
- Umgebungsvariable `VORCE_SELF_HOSTED_RUN_VISUAL_AUTOMATION=true` steuert ggf. CI-Skripte, aendert aber aktuell nichts an der Rust-Ebene, wo die Tests explizit `#[ignore]` sind und manuell aufgerufen werden muessen.

### Abgrenzung zu Output/Projector QA
Diese Smoke-Baseline pruft **nur** das Main-Window, das Initial-Rendering und das `wgpu`-Readback.
Sie ist **nicht** dafuer zustaendig, eine Matrix von Multi-Projector-Setups, unterschiedlichen Outputs (Spout, NDI), oder komplexem Window-Management (Keystone, Warping) abzudecken. Diese erweiterten Features obliegen der manuellen/erweiterten Output-QA. Die Baseline garantiert lediglich, dass die Render-Pipeline und die Export-Mechanismen fuer Automation grundsachlich funktionieren.

## Lokale Nutzung des Automation-Modus

Der Automationsmodus kann lokal zum Erstellen von deterministischen Screenshots verwendet werden:

```bash
cargo run --bin Vorce -- --mode automation \
  --fixture ./tests/fixtures/test_project.vorce \
  --exit-after-frames 60 \
  --screenshot-dir ./target/automation_test_output
```

Damit laedt Vorce das Test-Projekt (`.vorce`), laesst es 60 Frames laufen, speichert einen Screenshot und beendet sich vollautomatisch.

## Zukuenftige Multimodale Artefaktauswertung

Die erstellten Screenshots (sowohl aus dem Harness als auch dem E2E-Automation-Pfad) werden im self-hosted CI-Runner in dedizierten Ordnern wie `artifacts/visual-capture` gesammelt.
Diese koennen zusammen mit Metadaten (`pr_number`, `commit_sha`) verpackt werden, um spaeter ueber externe Tools oder LLMs ausgewertet zu werden. Der aktuelle Code-Stand stellt dafuer die rohen PNG-Bilder bereit.
