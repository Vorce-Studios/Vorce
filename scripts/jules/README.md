# Jules PowerShell

PowerShell-Skripte fuer die Jules REST API mit optionaler GitHub-Issue-Synchronisation.

## Voraussetzungen

- `JULES_API_KEY` als Umgebungsvariable oder per `-ApiKey`
- `gh` CLI fuer Issue-Integration
- Repository muss in Jules als Source verbunden sein

## Skripte

- `create-jules-session.ps1`: Erstellt Jules Sessions direkt aus `-IssueNumber` oder `-Prompt`
- `monitor-jules-sessions.ps1`: Listet Sessions, Status, Attention-Zustaende und letzte Aktivitaeten
- `respond-jules-session.ps1`: Reagiert auf Sessions mit `approvePlan` und `sendMessage`

## Beispiele

```powershell
./scripts/jules/create-jules-session.ps1 -IssueNumber 123 -AutoCreatePr
./scripts/jules/create-jules-session.ps1 -Prompt "Refactor the OSC routing layer" -Repository MrLongNight/MapFlow
./scripts/jules/monitor-jules-sessions.ps1 -OnlyActive -IncludeActivities
./scripts/jules/monitor-jules-sessions.ps1 -IssueNumber 123 -SyncIssueBody
./scripts/jules/respond-jules-session.ps1 -IssueNumber 123 -ApprovePlan
./scripts/jules/respond-jules-session.ps1 -IssueNumber 123 -Message "Bitte nutze die bestehenden UI-Komponenten in crates/mapmap-ui."
```

## GitHub-Issue-Felder

Standard-GitHub-Issues haben per REST API keine frei definierbaren Custom Fields. Die Skripte schreiben deshalb einen verwalteten Block `## Jules Automation` in den Issue-Body und koennen zusaetzlich Kommentare posten.
