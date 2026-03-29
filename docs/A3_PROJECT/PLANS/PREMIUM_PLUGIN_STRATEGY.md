# Strategie: Premium-Plugins & Lizenzschutz für VjMapper

Dieses Dokument beschreibt die technische und rechtliche Machbarkeit von kostenpflichtigen Zusatzfunktionen (Premium-Plugins) für VjMapper, unter Berücksichtigung der bestehenden GPL-3.0-Lizenz.

## 1. Rechtliche Rahmenbedingungen (GPL-Compliance)

VjMapper ist unter der **GPL-3.0-only** lizenziert. Dies bedeutet, dass alle "abgeleiteten Werke" (derivative works) ebenfalls unter GPL stehen müssen.

### Das Problem:
Plugins, die direkt als Rust-Crates eingebunden oder dynamisch (DLL) geladen werden, gelten rechtlich oft als Teil des Hauptprogramms und müssen daher ebenfalls Open Source sein.

### Die Lösung: Out-of-Process Isolation
Um proprietäre Plugins (geschlossener Quellcode, kostenpflichtig) zu ermöglichen, müssen diese als **eigenständige Prozesse** laufen.
- **Architektur**: Das Plugin ist eine separate `.exe`.
- **Kommunikation**: Daten werden über eine "Arm's Length" Schnittstelle (IPC - Inter-Process Communication) ausgetauscht.
- **Schnittstellen**: MCP (Model Context Protocol), JSON-RPC über Websockets oder Named Pipes.

## 2. Technische Umsetzung

### A. Steuerung & Daten (Die Bridge)
VjMapper fungiert als Host und stellt Parameter (Slider, Buttons, Audio-Analyse-Werte) bereit. Das Plugin empfängt diese Daten und sendet seine Ergebnisse zurück.

### B. Video-Datenaustausch (Texture Sharing)
Für VJ-Plugins ist eine hohe Performance bei der Grafikübertragung kritisch.
- **Spout (Windows)**: Nutzt Shared Memory auf der GPU. Extrem schnell, nahezu null Latenz. Ideal für lokale Plugins.
- **NDI**: Netzwerkbasiert. Erlaubt es, Plugins sogar auf einem zweiten PC im selben Netzwerk laufen zu lassen.

## 3. Lizenz- & Geschäftsmodelle

| Modell | Beschreibung | Vorteil | Nachteil |
| :--- | :--- | :--- | :--- |
| **Einmalkauf** | Nutzer zahlt einmal pro Plugin/Funktion. | Hohe Akzeptanz, geringer Support. | Kein stetiger Cashflow. |
| **Abonnement** | Monatliche/Jährliche Gebühr. | Regelmäßige Einnahmen. | Erfordert ständige Updates/Wartung. |
| **Feature-Unlock** | In-App Kauf schaltet Kernfunktionen frei. | "Gefühlte" Integration. | Schwerer bei GPL umzusetzen. |

## 4. Schutz gegen Softwarepiraterie (DRM)

Um den unbefugten Kopierschutz zu gewährleisten, wird ein mehrstufiges System empfohlen:

1.  **Hardware-ID (HWID) Binding**:
    - Das Plugin generiert beim ersten Start eine ID basierend auf Hardware-Komponenten (CPU, Mainboard, MAC-Adresse).
    - Die Lizenz wird serverseitig an diese ID gebunden.
2.  **Online-Validierung**:
    - Das Plugin kontaktiert beim Start einen Lizenz-Server (Cloud).
    - Prüfung auf Gültigkeit des Keys und Übereinstimmung der HWID.
3.  **Digitale Signatur**:
    - VjMapper akzeptiert nur Verbindungen von Plugins, die mit einem privaten Schlüssel (RSA/ED25519) des Entwicklers signiert sind.
    - Dies verhindert, dass Dritte "gecrackte" Versionen oder eigene Plugins als Premium-Features tarnen.

## 5. Roadmap & Nächste Schritte

1.  **Phase 1**: Stabilisierung der `vorce-ffi` und `vorce-mcp` Schnittstellen für externe Kommunikation.
2.  **Phase 2**: Implementierung eines Prototyps für Texture-Sharing (Spout) in VjMapper.
3.  **Phase 3**: Aufbau eines einfachen Lizenz-Servers (Node.js/Firebase) für Testzwecke.
4.  **Phase 4**: Entwicklung eines Beispiel-Plugins (z.B. "Pro NDI Output"), das den gesamten Lizenz-Workflow demonstriert.

---
*Erstellt am 29. März 2026 von Gemini CLI Agent.*
