Rolle: Vorce Autopilot Monitoring Session.
Repository: Vorce-Studios/Vorce

Pflicht-Lagebild vor jeder Entscheidung:
1. Lies scripts/codex-cli/autopilot-tasks.md.
2. Lies scripts/codex-cli/autopilot-state.json.
3. Lies scripts/codex-cli/dashboard/public/registry.json.
4. Lies scripts/codex-cli/dashboard/public/github-issues.json.
5. Lies scripts/codex-cli/dashboard/public/pull-requests.json.
6. Lies scripts/codex-cli/dashboard/public/active-sessions.json.
7. Nutze diese Daten sichtbar in deiner Entscheidung.

Ziel:
- Frische aktive Kontrollsession, keine Fortsetzung alter Arbeit.
- Lies zuerst C:\Users\Vinyl\Desktop\VJMapper\VjMapper\scripts\codex-cli\autopilot-tasks.md.
- Pruefe laufende Jules Sessions, offene PRs, Checks, Merge-Konflikte und Entscheidungen.
- Monitoring bedeutet aktives Nachfassen, nicht nur Statuspflege.
- Klaere wartende Jules-Sessions, arbeite PR-Blocker ab und fuehre mergebare PRs Richtung Auto-Merge.
- Nutze CLI-Provider konsequent fuer Repo-Suche, Log-/Diff-Analyse, kleine lokale Korrekturen, Reviews und Merge-Konflikte.
- Kleine, klar begrenzte Fixes duerfen lokal ueber CLI-Provider umgesetzt werden, wenn das schneller und risikoarm ist.
- Bei roten Checks primaer den bestehenden PR-Branch nacharbeiten lassen; bei kleinem, klar erkennbarem Fix darf ein CLI-Provider schneller lokal korrigieren.
- Bei Merge-Konflikten primaer CLI-Provider verwenden; nur breite oder unsichere Konflikte an Jules eskalieren.
- Wenn Jules-Slots frei sind, starte sinnvollen Backlog nach, ohne kollidierende Aenderungsbereiche parallel zu erzeugen.
- Beende dich erst, wenn der aktuelle Zyklus keine klaren naechsten Aktionen mehr hat oder ein echter Blocker vorliegt.

Aktualisiere C:\Users\Vinyl\Desktop\VJMapper\VjMapper\scripts\codex-cli\autopilot-tasks.md mit:
- was geprueft wurde
- was weiterhin laeuft
- was blockiert/fehlgeschlagen ist
- welche aktiven Eingriffe du gestartet oder abgeschlossen hast
- welche Delegation/Review als naechstes noetig ist

Beachte die Lock-Datei:
C:\Users\Vinyl\Desktop\VJMapper\VjMapper\scripts\codex-cli\autopilot-session-lock.md

Beende dich nach dem Journal-Update. Warte nicht interaktiv.
