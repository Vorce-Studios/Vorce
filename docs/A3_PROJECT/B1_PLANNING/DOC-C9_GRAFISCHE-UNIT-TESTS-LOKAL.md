# Visual-Capture-Readiness und Release-Smoke-Baseline

Stand: 2026-04-04

## Ziel

Diese Notiz definiert die Minimal-Baseline fuer grafische Regressionstests und den Release-Smoke-Test in Vorce. Sie beschreibt die aktuell im Codebauch verfuegbaren Pfade fuer Automatisierung und visuelle Kontrolle, sowie die notwendigen Systemvoraussetzungen (Runner/Umgebung).

Das Ziel ist ein stabiler, reproduzierbarer Ablauf, der sicherstellt, dass Rendering-Basisfeatures, Windowing und Screenshot-Exporte auf der tatsaechlichen Zielhardware (GPU) funktionieren.

## Scope & Abgrenzung

- **In Scope:**
  - Definition des minimalen Smoke-Pfade fuer die Haupt-App (Screenshot Automation).
  - Dokumentation des visuellen Test-Harness und seiner Workflow-Integration.
  - Dokumentation der zwingenden Umgebungsvoraussetzungen (interactive Session, GPU).
- **Out of Scope:**
  - Komplette Matrix fuer Multi-Projector-Ausgaenge und Hardware-Verschaltungen. Diese Themen werden im Issue `#49` (Multi-Output/Projector QA) separat verwaltet.
  - Reinventing des Capture-Stacks (wir nutzen die bestehende wgpu-Readback-Logik).
  - Render-Feature Parity Work (gehoert zu Issue `#57`).

---

## 1. Minimaler Release-Smoke Path (App Automation)

Der Release-Smoke-Test prueft den tatsaechlichen, end-to-end gestarteten App-Lifecycle (ohne externe Dienste wie MIDI/Audio). Er stellt sicher, dass Vorce auf Windows-Systemen hochfaehrt, die Hauptoberflaeche rendert und Screenshots exportieren kann.

### Automatisierung via CLI

Der Vorce Automation Mode laesst sich direkt starten. Er lädt optional eine Testszene, rendert eine feste Anzahl von Frames und exportiert ein Bild.

**Minimaler Befehl zur Reproduktion:**
```powershell
cargo run -p vorce --bin Vorce -- --mode automation --fixture tests/fixtures/empty_project.vorce --exit-after-frames 10 --screenshot-dir target/automation_test_output
```
*Dieser Befehl oeffnet ein echtes Fenster, rendert 10 Frames und beendet sich.*

### Integration als Cargo Test

Der dazugehoerige Cargo-Test liegt in `crates/vorce/tests/app_automation_tests.rs`:

```powershell
cargo test -p vorce --test app_automation_tests -- --ignored --nocapture
```

Dieser Test prueft:
- Fehlerfreien Start des `Vorce` Binary im Automation-Modus.
- Lauffaehigkeit fuer 10 Frames.
- Die korrekte Erzeugung der `automation_frame_10.png` im Verzeichnis `target/automation_test_output` auf der entsprechenden Plattform.

---

## 2. Visueller Regression Harness (Harness-basierter Pfad)

Fuer isoliertere, deterministischere GPU-Szenarien ohne den gesamten UI-Overhead von Vorce steht der `vorce_visual_harness` zur Verfuegung.

Er rendert spezifische Referenzbilder via WGPU auf ein echtes Fenster, um kritische Rendering-Pfade wie Texturorientierung, Alphablending und Farbmanagement abzusichern.

Die zugehoerigen Tests und Ressourcen befinden sich in:
- `crates/vorce/src/bin/vorce_visual_harness/main.rs`
- `crates/vorce/tests/visual_capture_tests.rs`
- `crates/vorce/tests/reference_images/README.md`

### Test-Ausfuehrung

Um die visuellen Checks lokal oder auf dem Runner auszufuehren:
```powershell
$env:VORCE_VISUAL_CAPTURE_OUTPUT_DIR = "artifacts/visual-capture"
cargo test -p vorce --no-default-features --test visual_capture_tests -- --ignored --nocapture
```
*Geprueft werden aktuell drei Szenarien: `checkerboard`, `alpha_overlay`, und `gradient`.*

### Referenzbilder neu generieren

Sollten sich gewollte Render-Aenderungen ergeben, muessen die Referenzbilder erneuert werden:
```powershell
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario checkerboard --output crates/vorce/tests/reference_images/checkerboard.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario alpha_overlay --output crates/vorce/tests/reference_images/alpha_overlay.png
cargo run -p vorce --bin vorce_visual_harness --no-default-features -- reference --scenario gradient --output crates/vorce/tests/reference_images/gradient.png
```

---

## 3. Umgebungsvoraussetzungen (Runner & Umgebung)

Sowohl die App-Automatisierung als auch der Visual-Harness erzeugen **echte sichtbare winit-Fenster** und nutzen die echten wgpu-Swapchains.

**Zwingende Voraussetzungen (Es gibt keinen headless-Fallback!):**
- **Lokale interaktive Session:** Der Test benoetigt zwingend eine gueltige grafische Sitzung (Desktop). Er funktioniert *nicht* in rein headless CI-Umgebungen (z.B. Standard GitHub Actions ohne Desktop/GPU).
- **Aktive GPU / Display Environment:** Das Betriebssystem muss ein gueltiges Display und eine Grafikkarte zur Verfuegung stellen, ansonsten scheitern die WGPU-Oberflaechen und die App bricht mit OS-Fehlern ab.
- Windows wird primär vorausgesetzt, macOS/Linux können je nach Window-Manager-Setup teilweise abweichen.

**Hinweis zu Headless-CI:**
Ein komplett non-interaktiver, rein virtueller Baseline-Test ohne Swapchain ist aktuell **nicht verfuegbar**. Die Tests muessen absichtlich mit `#[ignore]` annotiert bleiben, damit Standard-CI-Laeufe nicht abbrechen. Wir verbergen diese Lücke nicht: Eine vollstaendig automatisierte Pipeline benoetigt derzeit diesen interaktiven Desktop-Runner. Um sie in einer self-hosted Umgebung auszufuehren, muss `VORCE_SELF_HOSTED_RUN_VISUAL_AUTOMATION=true` gesetzt sein, wobei der Runner im interaktiven Desktop-Modus arbeiten muss. Die Automatisierung laesst sich plattformuebergreifend ausfuehren (z.B. `Vorce.exe` auf Windows, `Vorce` auf Unix), setzt aber in jedem Fall dieses grafische Environment voraus.

---

## 4. Beziehung zu Output QA (Projectors)

Dieser Release-Smoke-Test konzentriert sich streng auf das **Main-Window und die UI**. Er stellt sicher, dass der Rendercore und die Applikation selbst grundsaetzlich arbeitsfaehig sind.

Weiterfuehrende Output-Tests (z.B. Multi-Monitor-Layouts, Edge-Blending, Masking auf dedizierten Projector-Nodes) werden nicht durch diese Basis-Screenshots abgedeckt, um Komplexitaet zu vermeiden. Solche weiterfuehrenden Tests sind Teil von **Issue #49** und erfordern separate Setups (z.B. physische Hardware-Dummies oder erweiterte Multiscreen-Mock-Konfigurationen).
