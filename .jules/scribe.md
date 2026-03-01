# Scribe Journal - 2026-02-15

## Documentation Fixes & Updates

I have addressed several broken links and outdated status indicators in the documentation.

### Actions Taken
- **Broken Links Fixed**:
  - `README.md`: Pointed "Installation" link to `docs/01-GETTING-STARTED/INSTALLATION.md` (was `docs/08-TECHNICAL/SETUP_GUIDE.md`).
  - `docs/10-CICD_PROZESS/WORKFLOW_CONTROL.md`: Pointed "Support" link to `docs/01-GETTING-STARTED/INSTALLATION.md` (was `.github/SETUP_GUIDE.md`).
- **Roadmap Update**:
  - Updated "Render Pipeline & Module Logic" status in `ROADMAP.md` to reflect that the main application entry point is implemented and stabilization is in progress.
- **Changelog Update**:
  - Added missing entry for 2026-02-06 ("Safe Reset Clip" feature).

### Observations
- The `docs/` structure is comprehensive but has some legacy references to files that have been moved or renamed.
- `ROADMAP.md` status fields need regular manual verification against the Changelog.

## 2026-03-01 - Platzhalter-Screenshots im Wiki-Handbuch
 **Erkenntnis:** Das User-Wiki (`docs/user/wiki_manual/`) war stark mit Bild-Platzhaltern und WIP-Anmerkungen verseucht, was den Scribe-Regeln (`Niemals tun: - Placeholder-Text`) widerspricht. Platzhalter stören den Lesefluss und verringern den professionellen Eindruck.
 **Aktion:** Ich habe alle Platzhalter (z.B. `> 🖼️ **[PLATZHALTER SCREENSHOT: ...]**`) sowie temporäre WIP-Warnungen systematisch aus den `docs/user/wiki_manual/*.md`-Dateien entfernt.
