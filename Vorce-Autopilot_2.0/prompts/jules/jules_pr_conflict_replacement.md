Rolle: Jules Replacement Implementation Executor.
Repository: $Repository
Ersetze die Arbeit aus dem geschlossenen Konflikt-PR #$PullRequestNumber.
Basisbranch: $BaseRefName
Alter PR-Titel: $PullRequestTitle

Ziel:
Erstelle die kleinste saubere Neuimplementierung des fachlichen PR-Ziels auf aktuellem `$BaseRefName`, weil der alte Branch zu viele Merge-Konflikte hatte.

Regeln:

- Kein Versuch, den alten Konflikt-Branch weiter zu retten.
- Halte den Scope eng am alten PR-Ziel.
- Erstelle einen neuen PR auf frischer Basis.
- Dokumentiere Abweichungen zum alten PR kurz im neuen PR.
