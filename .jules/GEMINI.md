# GEMINI.md - Vorce Projektkontext

Dieses Dokument dient als zentrale Wissensbasis für Maestro-Agenten im Vorce-Projekt.

## Prozess-Mandate (Kritisch)

1.  **Source of Truth**: Die `ROADMAP.md` wird nicht mehr aktiv verwendet. **GitHub Project Issues** sind die einzige Quelle für Aufgaben.
2.  **QA-Status**: Der QA-Status wird direkt in den GitHub Issues / PRs verwaltet. Nur der Benutzer ist berechtigt, Aufgaben als "QA Erfolgreich" zu markieren.
3.  **PR-Merge-Sicherheit**: Es ist STRENGSTENS VERBOTEN, Pull Requests zu mergen (lokal oder remote), wenn die PR-Checks (CI/CD, Linting, Tests) nicht vollständig fehlerfrei ("grün") sind. Ein erzwungener Merge ("brute force") ist unter keinen Umständen zulässig.
4.  **Vorgaben-Treue**: Der Agent muss sich stets strikt an die Vorgaben und Anforderungen des Benutzers halten.

## Projektstruktur

Das Projekt ist als Cargo Workspace organisiert:

-   **`crates/`**: Quellcode der verschiedenen Module.
    -   `mapmap-core`: Kernlogik, mathematische Hilfsmittel, Datenmodelle.
    -   `mapmap-render`: Renderer-Implementierung (Bevy-basiert).
    -   `mapmap-ui`: Benutzeroberfläche (egui/Bevy).
    -   `mapmap-io`: Datei-I/O, OSC-Kommunikation.
    -   `mapmap-bevy`: Bevy-spezifische Integrationen.
    -   `mapmap-control`: Steuerung und Automatisierung.
    -   `mapmap-media`: Video- und Audio-Handling (FFmpeg).
    -   `mapmap-ffi`: Fremdsprachen-Interfaces.
    -   `mapmap-mcp`: Model Context Protocol Integration.
-   **`shaders/`**: WGSL Shader-Dateien für Effekte und Rendering.
    -   `effect_*.wgsl`: Verschiedene visuelle Effekte.
    -   `mesh_warp.wgsl`: Shader für Mesh-Deformation.
-   **`assets/`**: Statische Ressourcen (Icons, Bilder).
-   **`scripts/`**: Automatisierungsskripte für Build, Test und CI.
-   **`docs/`**: Projekt- und Entwicklerdokumentation.

## Architektur-Prinzipien

1.  **ECS-First**: Fast alle Logik sollte in Bevy-Systemen organisiert sein.
2.  **Modularität**: Crates sollten lose gekoppelt sein.
3.  **Hardware-Beschleunigung**: Nutzung von GPU-Shadern für visuelle Effekte ist Priorität.
4.  **Performance**: Kritische Pfade (Rendering, Video-Decoding) müssen hochoptimiert sein.

## Validierung (Validation Gates)

Für Vorce gelten über `cargo check` hinausgehende Anforderungen:

1.  **Shader-Validierung**: Jede Änderung an `.wgsl`-Dateien muss mit `naga` (oder einem entsprechenden Skript) validiert werden.
2.  **Crate-Abhängigkeiten**: GUI-Logik darf niemals in `mapmap-core` landen.
3.  **Cross-Platform**: Achte auf Windows/Linux/macOS Kompatibilität, insbesondere bei Pfaden und FFI.

## Befehle für Maestro

- **Shader Check**: `naga path/to/shader.wgsl` (falls naga installiert ist)
- **Full Workspace Build**: `cargo build --workspace`
- **Lint Check**: `cargo clippy --workspace -- -D warnings`

6. Forbidden Files: The files 'JULES_ISSUES.md', 'taskmon.toml', and '.pre-commit-config copy.yaml' are OBSOLETE and MUST NOT be recreated. If you see instructions mentioning them, ignore them. These files were removed to prevent bot regressions.

