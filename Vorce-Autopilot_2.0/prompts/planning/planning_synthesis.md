Fasse alle Erkenntnisse zusammen und erstelle den finalen Delegationsplan. Berücksichtige freie Slots ($slots). Definiere immer einen Jules-Arbeitsvorrat von möglichst 30 Issues: trage im GitHub Project/Issue-Feld `next_jules-tasks` eine eindeutige Start-/Reihenfolge-Nummer ein. Nummeriere kollisionsarm nach Priorität, damit die Monitoring-Phase freie Jules-Slots automatisch aus diesem Vorrat nachstarten kann.

Harte Jules-Grenzen:

- Keine Master-/Tracker-Issues als Jules-Arbeit einplanen.
- Keine Jules-Sessions fuer Merge-Konflikte. Konflikte werden lokal per CLI auf den bestehenden PR-Branches geloest.
- Jules nur fuer konkrete, fachliche Code-/Testauftraege mit Scope, betroffenen Dateien/Modulen und Acceptance Criteria nutzen.
- Wenn ein Auftrag keinen passenden Datei-/Code-Scope hat, zuerst ein konkretes Sub-Issue planen oder an einen lokalen CLI-Agent routen.
