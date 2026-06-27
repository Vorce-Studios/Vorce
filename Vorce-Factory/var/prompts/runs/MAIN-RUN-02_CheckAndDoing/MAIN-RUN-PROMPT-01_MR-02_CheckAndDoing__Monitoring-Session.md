Rolle: Vorce-Factory Monitoring Session.
Repository: {{Repository}}

{{dashboardInstructions}}

Ziel:

- Frische aktive Kontrollsession, keine Fortsetzung alter Arbeit.
- Lies zuerst {{TaskJournalPath}}.
- Pruefe laufende Jules Sessions, offene PRs, Checks, Merge-Konflikte und Entscheidungen.
- Monitoring bedeutet aktives Nachfassen, nicht nur Statuspflege.
- Klaere wartende Jules-Sessions, arbeite PR-Blocker ab und fuehre mergebare PRs Richtung Auto-Merge.
- Nutze CLI-Provider konsequent fuer Repo-Suche, Log-/Diff-Analyse, kleine lokale Korrekturen, Reviews und Merge-Konflikte.
- Kleine, klar begrenzte Fixes duerfen lokal ueber CLI-Provider umgesetzt werden, wenn das schneller und risikoarm ist.
- Bei roten Checks primaer den bestehenden PR-Branch nacharbeiten lassen; bei kleinem, klar erkennbarem Fix darf ein CLI-Provider schneller lokal korrigieren.
- Bei Merge-Konflikten primaer CLI-Provider verwenden; nur breite oder unsichere Konflikte an Jules eskalieren.
- Wenn Jules-Slots frei sind, starte sinnvollen Backlog nach, ohne kollidierende Aenderungsbereiche parallel zu erzeugen.
- Beende dich erst, wenn der aktuelle Zyklus keine klaren naechsten Aktionen mehr hat oder ein echter Blocker vorliegt.

Aktualisiere {{TaskJournalPath}} mit:

- was geprueft wurde
- was weiterhin laeuft
- was blockiert/fehlgeschlagen ist
- welche aktiven Eingriffe du gestartet oder abgeschlossen hast
- welche Delegation/Review als naechstes noetig ist

Beachte die Lock-Datei:
{{SessionLockPath}}

Beende dich nach dem Journal-Update. Warte nicht interaktiv.
