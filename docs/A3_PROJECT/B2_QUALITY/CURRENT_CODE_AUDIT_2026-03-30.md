# Intensiver Code-Audit-Bericht (Stand 30. März 2026)

**Methodik:** 
1. Unabhängige statische Analyse (`cargo clippy`, `cargo audit`, Architektur-Scan) des aktuellen `main` Branches.
2. Abgleich und Konsolidierung mit historischen Audit-Berichten (Stand 23.03.2026), um blinde Flecken der Automatisierung zu decken.

---

## 1. Baseline Code Quality & Logik (Aktueller Stand)

**ERFREULICH:** Die Basis-Codequalität hat sich massiv verbessert.
*   **Clippy:** Ein vollständiger `cargo clippy --workspace --all-targets` Lauf schließt **ohne Warnungen** ab. Das ist ein exzellentes Zeichen für die Disziplin bei der Code-Integration und zeigt, dass formale Logikfehler, Anti-Patterns und ungenutzter Code (Dead Code) systematisch bereinigt wurden.
*   **Zustandsmanagement:** Die Architektur rund um `AppState` nutzt `Arc`-basiertes Copy-on-Write (`Arc::make_mut`). Dies ist ein sehr robustes Pattern für Thread-Sicherheit und Undo/Redo-Systeme in Rust, erfordert jedoch weiterhin Achtsamkeit, um unbeabsichtigte teure Deep-Clones zu vermeiden.

---

## 2. Dependency-Risiken & Security (Cargo Audit)

Mein aktueller Security-Scan hat **5 offene Schwachstellen/Warnungen** in der `Cargo.lock` identifiziert, die dringend adressiert werden müssen:

1.  **`atty` (v0.2.14)**: *Unmaintained & Unsound (RUSTSEC-2021-0145 / RUSTSEC-2024-0375)*. Wird transitiv über `env_logger` -> `autocxx-build` in `vorce-io` hereingezogen. Sollte durch die native Rust `IsTerminal` Trait (ab 1.70) ersetzt werden.
2.  **`bincode` (v1.3.3 & v2.0.1)**: *Unmaintained (RUSTSEC-2025-0141)*. Wird von `webrtc-dtls` und `ableton-link-rs` verwendet. Dass zwei Versionen gleichzeitig im Baum existieren, bläht die Binary auf. Zudem ist v1.x bei untrusted Inputs anfällig für DoS.
3.  **`paste` (v1.0.15)**: *Unmaintained (RUSTSEC-2024-0436)*. Ein reines Makro-Utility, daher zur Laufzeit ungefährlich, sollte aber langfristig ersetzt werden.

---

## 3. Architektur-Schwachstellen & Flaschenhälse

Hier fließen meine unabhängigen Architektur-Scans mit den validierten Alt-Erkenntnissen zusammen:

### 3.1 WGPU-Versionskonflikte (Anhaltendes Risiko)
*   Obwohl heute Dependency-Updates für `wgpu` auf **v29.0.1** (für `vorce`, `vorce-render`, etc.) durchgeführt wurden, zeigt der Audit-Baum, dass **`vorce-bevy`** (bzw. `bevy_render` 0.16.1) weiterhin intern an **`wgpu 24.0.5`** hängt.
*   **Konsequenz:** Dieser Versions-Clash im Workspace ist extrem gefährlich. Er kann zu Linker-Fehlern, Laufzeitabstürzen und inkompatiblen WGPU-Instanzen führen.

### 3.2 Performance-Bottlenecks im Render-Pfad
*   **Engine-Isolation (Bevy vs. Vorce):** Der Datenaustausch von Frame-Daten zwischen dem Bevy-ECS und dem Standard-Render-Pfad erfordert teure **GPU-CPU-GPU Kopien**.
*   **Synchrone Queues:** Der Texture-Uploader in `vorce-render` nutzt synchrone Queues.
*   **Konsequenz:** In Kombination stellen diese beiden Punkte einen massiven Flaschenhals bei hohen Auflösungen (4K) oder komplexen 3D-Szenen dar. Es muss zwingend auf asynchrone Staging-Belts und (falls möglich) Shared-Texture-Handles (Zero-Copy) zwischen Bevy und dem Vorce-Renderer umgestellt werden.

### 3.3 Legacy Code & Technische Schulden
*   **Shape vs. Mesh:** In `vorce-core` existieren noch Legacy-Pfade für alte Geometrie-Typen, die den neuen `Mesh`-Ansatz verkomplizieren.
*   **imgui-Reste:** Obwohl die UI auf `egui` läuft, befinden sich laut Alt-Berichten noch Reste von `imgui` im Workspace-Vendor-Bereich, die bereinigt werden müssen.

---

## 4. Sicherheit & Unsafe Code (Aus Alt-Bericht übernommen & verifiziert)

Ein automatisierter Linter übersieht oft logische Mängel in `unsafe`-Blöcken, wenn diese syntaktisch korrekt sind.
*   **FFI-Grenzen (FFmpeg/HAP):** In Dateien wie `hap_player.rs` und `decoder.rs` fehlen die konsequenten `// SAFETY:` Dokumentationen.
*   **Risiko:** Pointer-Dereferenzierungen ohne ausreichende Null- oder Boundary-Checks an den C-FFI-Grenzen sind ein hohes Risiko für Segfaults, insbesondere bei korrupten Media-Dateien. Ein manuelles Security-Audit dieser spezifischen Dateien ist erforderlich.

---

## 5. Fazit & Handlungsanweisungen

Das Projekt hat eine exzellente Basis-Hygiene erreicht (Zero Clippy Warnings). Die verbleibenden Baustellen sind struktureller und architektonischer Natur.

**Prioritätenliste für die nächsten Sprints:**
1.  **Blocker lösen:** Den `wgpu` Versionskonflikt zwischen Bevy (v24) und dem Rest des Projekts (v29) auflösen.
2.  **Abhängigkeiten härten:** Veraltete Crates (`atty`, `bincode`) aus dem Dependency-Tree entfernen oder ersetzen.
3.  **Performance optimieren:** Zero-Copy-Strategien zwischen Bevy und Vorce-Render evaluieren und synchrone Texture-Uploads asynchronisieren.
4.  **FFI-Sicherheit:** Unsafe-Code-Blöcke im Media-Decoder zwingend dokumentieren (`// SAFETY:`) und Boundary-Checks nachrüsten.