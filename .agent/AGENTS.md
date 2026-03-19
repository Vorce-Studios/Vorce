# AGENTS.md - Anweisungen für KI-Agenten

Hallo Jules! Dieses Dokument enthält technische Anweisungen für die Arbeit am VjMapper-Projekt.

## Projektübersicht

VjMapper ist ein Rewrite einer C++/Qt-Anwendung in Rust. Ziel ist eine hochperformante, speichersichere Projection-Mapping-Software. Der gesamte Quellcode befindet sich im `crates/`-Verzeichnis, organisiert als Cargo Workspace.

## Wichtigste Anweisung

**Kommuniziere mit dem Benutzer ausschließlich auf Deutsch.** Alle Pläne, Fragen und Antworten müssen auf Deutsch sein.

## Setup & Build-Befehle

-   **Abhängigkeiten installieren:** (Siehe `README.md` für plattformspezifische Bibliotheken)
-   **Projekt bauen (Entwicklung):**
    ```bash
    cargo build
    ```
-   **Projekt bauen (Optimiert für Release):**
    ```bash
    cargo build --release
    ```
-   **Anwendung starten:**
    ```bash
    cargo run --release
    ```

## Code-Stil & Konventionen

-   **Formatierung:** Der Code muss mit `cargo fmt` formatiert werden.
-   **Linting:** Führen Sie `cargo clippy` aus, um häufige Fehler zu vermeiden.
-   **API-Design:** Halten Sie sich an die [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/).
-   **Dokumentation:** Alle öffentlichen Funktionen und Module müssen mit `///` dokumentiert werden.

## Test-Anweisungen

-   **Alle Tests ausführen:**
    ```bash
    cargo test
    ```
-   **Anforderung:** Fügen Sie für jede neue Funktion oder Fehlerbehebung entsprechende Unit-Tests hinzu. Bestehende Tests dürfen nicht fehlschlagen.

## Spezialisierte KI-Agenten

### 1. Shader-Spezialist (shader_specialist)

```yaml
---
name: shader_specialist
tools: [read_file, grep_search, glob, run_shell_command, web_fetch, google_web_search]
model: gemini-2.0-flash
---
```

- **Fokus:** WGSL-Shader-Entwicklung, Performance-Optimierung (GPU), Mathematische Algorithmen.
- **Anweisungen:** Nutze `naga` zur Validierung von `.wgsl` Dateien. Achte auf Bevy-Kompatibilität (`@group`, `@binding`). Vermeide redundante Berechnungen in Fragment-Shadern. Dokumentiere mathematische Modelle in Shaders mit Kommentaren.

### 2. Bevy-Architekt (bevy_architect)

```yaml
---
name: bevy_architect
tools: [read_file, grep_search, glob, run_shell_command, activate_skill]
model: gemini-2.0-flash
---
```

- **Fokus:** ECS-Design (Entities, Components, Systems), Plugin-Struktur, Ressourcen-Management.
- **Anweisungen:** Halte Systeme modular. Nutze `States` und `SystemSets` für die Ablaufsteuerung. Achte auf Thread-Safety und Minimierung von Lock-Contentions. Bevorzuge Event-basierte Kommunikation zwischen Crates.

### 3. PR & Branch Manager (pr_branch_manager)

```yaml
---
name: pr_branch_manager
tools: [read_file, grep_search, glob, run_shell_command, git_ops, web_fetch]
model: gemini-2.0-flash
---
```

- **Fokus:** Git-Flow, PR-Reviews, Fehleranalyse in CI/CD, Branch-Hygiene.
- **Anweisungen:**
  - **Proaktives Branch-Management:** Scanne regelmäßig nach unmerged Branches ohne PR. Prüfe deren Status (`git diff main..branch`). Falls sinnvoll, erstelle automatisch einen PR mit einer kurzen Analyse der Änderungen.
  - **CI/CD Fehler-Spezialist:** Wenn ein PR-Check fehlschlägt, analysiere sofort die Logs. Identifiziere die Ursache (z.B. fehlende Abhängigkeit, Shader-Validierung, Flaky Tests). Implementiere Fixes direkt im Branch.
  - **Reviews:** Achte auf Mapflow-spezifische Vorgaben (Keine GUI-Logik in Core-Crates, Shader-Validierung bestanden).
  - **Merging:** Merge erst, wenn alle Checks grün sind und der PR-Review-Status "Approved" ist.
  - **Aufräumen:** Lösche Branches nach dem Mergen automatisch (Hygiene).

## Pull Request (PR) Prozess

1.  **Vorbereitung:** Stellen Sie vor dem Einreichen sicher, dass die folgenden Befehle ohne Fehler durchlaufen:
    ```bash
    cargo fmt
    cargo clippy
    cargo test
    ```
2.  **Titel-Format:** Verwenden Sie klare und prägnante Titel, die die Änderungen zusammenfassen.
3.  **Kommunikation:** Erwähnen Sie `@MrLongNight` im PR, falls strategische Fragen offen sind. Feedback von Reviewern wird über PR-Kommentare gegeben.
