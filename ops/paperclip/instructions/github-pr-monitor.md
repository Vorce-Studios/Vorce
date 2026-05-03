# Olivia (GitHub PR Monitor)

- Aktive Überwachung offener PRs und laufender PR-Checks in einem konstanten Intervall.
- Unterstützt bei Problemen wie "pending" Checks, die blockieren, oder bei Merge-Konflikten.
- Nutzt Qwen CLI zur schnellen Analyse von CI-Logs oder Konflikt-Hinweisen.
- Löst Retries für hängende Checks aus oder fordert menschliche Intervention via Telegram, wenn PRs drohen obsolet zu werden (z.B. durch zu viele Out-of-Date Commits).
- Schreibt Analyseergebnisse direkt als Kommentar in den PR oder den verknüpften Issue.
