# Multi-Projector und Cluster-Output QA & Abnahmeschicht

Stand: 2026-04-04
Issue: #49

## Ziel

Dieses Dokument definiert eine belastbare QA- und Integrationstest-Basis für das lokale Multi-Projector-Subsystem und sichert die clusterrelevanten Output-Fälle explizit ab. Es adressiert die bisher fehlende Abnahmeschicht für Multi-Projector-Funktionalitäten.

---

## 1. Automatisierte und Reproduzierbare Tests (Lokale Pfade)

Für den lokalen Produktivbetrieb müssen diese Kernfälle als automatisierte CLI-Tests (z.B. via `--mode automation`) oder als klar reproduzierbare Fixture-Testfälle vorliegen:

### 1.1 Multi-Output Rendering
- **Testfall:** Laden eines Projekts mit mehreren konfigurierten Outputs (z.B. 2 physikalische Bildschirme).
- **Setup:** `cargo run -p vorce --bin Vorce -- --mode automation --fixture tests/fixtures/multi_output.vorce --exit-after-frames 30`
- **Erwartung:** Die Render-Pipeline erzeugt für jeden Output einen korrekten Framebuffer-Readback (Screenshot-Export), ohne dass es zu Zuweisungskonflikten oder Performance-Einbrüchen durch Ressourcenkonflikte in wgpu kommt.

### 1.2 Edge Blend Processing
- **Testfall:** Zwei Projektoren mit definiertem Überlappungsbereich (Overlap) und Edge Blend Kurve.
- **Setup:** `--fixture tests/fixtures/edge_blend.vorce`
- **Erwartung:** Im Readback-Screenshot ist der Gradientenverlauf an den Rändern korrekt berechnet (Gamma-korrekt) und es entstehen keine harten Kanten oder Artefakte im Überlappungsbereich.

### 1.3 Per-Output Konfiguration & Color Calibration
- **Testfall:** Individuelle Farbkorrektur (z.B. Helligkeit, Kontrast, Gamma) pro Output.
- **Setup:** `--fixture tests/fixtures/color_calibration.vorce`
- **Erwartung:** Die angewendeten Farbprofile (ICC oder Shader-basiert) wirken sich nur auf den dedizierten Output aus.

---

## 2. Manuelle QA-Checkliste (Hardware-Setup mit >= 2 Projektoren)

Da nicht alle physikalischen Gegebenheiten automatisiert testbar sind, muss vor Releases eine manuelle QA mit echten Hardware-Projektoren erfolgen:

- [ ] **Erkennung & Routing:**
  - Vorce erkennt alle angeschlossenen Projektoren über das OS (`winit` Displays).
  - Outputs lassen sich in der UI eindeutig einem Projektor zuweisen.
- [ ] **Vollbild & Windowing:**
  - Projektor-Fenster starten korrekt im Borderless Fullscreen auf dem richtigen Display.
  - Beim Minimieren/Wiederherstellen oder Monitor-Trennen stürzt die App nicht ab (`Surface` lost handling).
- [ ] **Geometrie & Warp:**
  - Keystone- oder Warp-Gitter lassen sich auf Output A anpassen, ohne Output B zu beeinflussen.
- [ ] **Edge Blend Visuell:**
  - Testbild (z.B. Grid) zeigt keine doppelten Pixel im Blend-Bereich.
  - Der Schwarzpegel (Black Level) ist auf beiden Projektoren visuell identisch justierbar.
- [ ] **Output-Ownership:**
  - Zuweisung eines Outputs an eine Vorce-Node exklusiv möglich; Konflikte (2 Nodes auf denselben Output) erzeugen eine sichtbare Warnung in der UI, blockieren aber nicht die Render-Schleife.

---

## 3. Clusterrelevante Output-Fälle (Smoke-/Integrations-Tests)

Wenn eine Instanz als lokaler Output-Knoten (Slave/HeadlessOutput) in einem größeren Multi-Instance-Setup läuft, gelten diese Smoke-Fälle:

### 3.1 Headless Slave Output
- **Szenario:** Instanz startet als dedizierter Slave ohne Main-UI, nur mit Projektor-Fenstern.
- **Prüfung:** Der Slave rendert ausschließlich die zugewiesenen Output-Slices. Empfängt er Netzwerk-Sync (Frame-Trigger), rendert er synchron. Bei Verlust der Control Plane rendert er den letzten Frame weiter (Fail-Safe) oder schaltet auf Schwarz (konfigurierbar).

### 3.2 Output-Ownership im Cluster
- **Szenario:** Master weist Output X an Slave A und Output Y an Slave B zu.
- **Prüfung:** Die Konfiguration (Session State) wird repliziert. Slave A versucht nicht, Ressourcen für Output Y zu allokieren.

---

## 4. Abschlusskriterien für MF-045

Die historischen MF-045 Anforderungen gelten als erfüllt, wenn folgende reproduzierbare Testfälle erfolgreich implementiert sind:

1. **TC-MF045-1 (Output Isolation):** Ein Projekt mit 3 `OutputType::Projector` Nodes wird geladen. Jeder Node modifiziert einen anderen Target-Screen. Das System leitet die korrekten Parameter (`target_screen`, `output_width`) an die `OutputConfig` und `WindowManager` weiter, ohne Crosstalk.
2. **TC-MF045-2 (Warp Serialization):** Eine komplexe Grid-Warp-Konfiguration für 2 Projektoren wird in der UI erstellt, gespeichert (`.vorce` Datei) und neu geladen. Die gerenderten Pixel-Positionen vor dem Speichern und nach dem Laden sind identisch.
3. **TC-MF045-3 (Cluster Output Dispatch):** Ein Master-Node delegiert eine Videospur-Renderanforderung aufgeteilt auf zwei Slave-Nodes. Die Slaves produzieren auf ihren lokalen Displays nahtlose Hälften des Videos synchron.

---
*Anmerkung: Die generelle Release-Smoke-Baseline ist in Issue #77 und Cluster-QA oberhalb des lokalen Subsystems in Issue #108 definiert.*
