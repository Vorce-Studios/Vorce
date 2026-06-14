Basierend auf der Analyse (Kontext: $context), schlage maximal $maxIssues neue Issues vor. Fokus auf kleine Standard-Issues für CLI-Agents. Antworte als JSON-Liste.

Harte Regeln:

- Keine Master-/Tracker-Issues als Jules-Coding-Task vorschlagen.
- Keine Jules-Sessions fuer Merge-Konflikte vorschlagen; Konflikte gehen immer an lokale CLI-Agents.
- `agent: "jules"` nur setzen, wenn das Issue einen konkreten Code-/Test-Scope mit Dateien/Modulen und Acceptance Criteria beschreibt.
- Fuer kleine Bugfixes, Skripte, CI, Tests, Konflikte und unklare Koordinationsarbeit lokale CLI-Agents waehlen.
