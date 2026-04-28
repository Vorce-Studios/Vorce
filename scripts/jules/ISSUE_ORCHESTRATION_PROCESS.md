# Jules Issue Orchestration

Ziel: Jules-Sessions reproduzierbar starten, aktive Sessions knapp monitoren, haengende Sessions zielgerichtet anschieben und offene PRs auf merge-ready halten.

## Standardfluss

1. Session anlegen

- `create-jules-session.ps1 -IssueNumber <n> -Repository <owner/repo> -AutoCreatePr`
- Optional `-RequirePlanApproval`, wenn die Aufgabe erst nach Planfreigabe loslaufen soll.

1. Session monitoren

- `monitor-jules-sessions.ps1 -Repository <owner/repo> -OnlyActive -IncludeActivities`
- Optional `-SyncIssueBody`, um den Managed-Block im GitHub-Issue nachzuziehen.

1. Attention-Zustaende behandeln

- `AWAITING_PLAN_APPROVAL`: mit `respond-jules-session.ps1 -IssueNumber <n> -ApprovePlan`
- `AWAITING_USER_FEEDBACK` oder `PAUSED`: entweder gezielte Rueckmeldung mit `respond-jules-session.ps1 -Message ...`
- Fuer konservative Auto-Hilfe: `monitor-jules-sessions.ps1 -OnlyActive -AutoRespondAttention`

1. PRs monitoren

- `monitor-jules-prs.ps1 -Repository <owner/repo>`
- Bei Bedarf `-AutoNudgeJules`, damit Jules direkt wegen Merge-Konflikten oder failing checks nacharbeitet.

1. Abschluss

- Wenn Session `COMPLETED` und PR/checks gruen sind: normales Review/Merge.
- Wenn Session `FAILED`: neuen Lauf nur starten, wenn der eigentliche Blocker verstanden ist.

## Empfohlene Routinen

### Jules Session Sweep

- Besitzer: Ben
- Frequenz: alle 15 Minuten waehrend aktiver Delivery-Phasen
- Kommando:

```powershell
./scripts/jules/monitor-jules-sessions.ps1 -Repository owner/repo -OnlyActive -IncludeActivities -SyncIssueBody
```

### Jules Attention Unblock

- Besitzer: Ben
- Trigger: `AWAITING_PLAN_APPROVAL`, `AWAITING_USER_FEEDBACK`, `PAUSED`
- Kommando:

```powershell
./scripts/jules/monitor-jules-sessions.ps1 -Repository owner/repo -OnlyActive -AutoApprovePlan -AutoRespondAttention -SyncIssueBody
```

Nur fuer konservative Standardantworten verwenden. Produktentscheidungen oder inhaltliche Aenderungen weiter manuell schicken.

### Jules PR Sweep

- Besitzer: Ben oder Lisa
- Frequenz: alle 20 Minuten waehrend offene Jules-PRs existieren
- Kommando:

```powershell
./scripts/jules/monitor-jules-prs.ps1 -Repository owner/repo -SyncIssueBody
```

### Jules PR Recovery

- Besitzer: Ben
- Trigger: Merge-Konflikt oder failing required checks
- Kommando:

```powershell
./scripts/jules/monitor-jules-prs.ps1 -Repository owner/repo -AutoNudgeJules -SyncIssueBody
```

## CEO-Statusreport

John sollte keinen breiten Sweep auf jeder Idle-Heartbeat fahren. Statusreports nur:

- on demand durch Board/CEO-Wake
- oder als gezielte Routine mit klarer Frage, z. B. "Erstelle den Wochenstatus fuer Delivery, Risiken, Budgetdruck und offene Entscheidungen."

Empfohlenes Format:

1. Delivery
2. Kritische Blocker
3. PR-/Check-Lage
4. Entscheidungen, die CEO/Board brauchen
5. Naechste 24h

Die Datenbasis dafuer sollte auf Ben/Lisa/Jules-Tracking und offenen in-review/blocked Issues begrenzt bleiben, nicht auf einen Vollscan der Firma.
