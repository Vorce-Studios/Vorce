# Agenten-Rollen & Werkzeuge

## Zentrales Wissensmanagement: Code-Atlas
Bevor Dateien im großen Stil gelesen werden, MUSS der Code-Atlas zur Orientierung genutzt werden.

- **Zweck**: Schnelle Suche nach Symbolen, Crates, Tags und Abhängigkeiten.
- **Aktualisierung**: `python scripts/dev-tools/generate-code-atlas.py`
- **Abfrage**: `python scripts/dev-tools/query-code-atlas.py "<begriff>"`
- **Beispiele**: 
  - `query-code-atlas.py "ffi"` (Schnittstellen finden)
  - `query-code-atlas.py "path:.wgsl"` (Shader finden)
  - `query-code-atlas.py "symbol:McpServer"` (Code-Stellen finden)

---

# Rollen
- **Gemini CLI Agent**: Der aktuelle Haupt-Agent für Implementierung und Planung.
- **Jules (Gemini)**: KI-Agent für Architektur und komplexes Debugging.
- **Codex CLI**: Tooling-Agent für Automatisierung und Code-Atlas Pflege.
