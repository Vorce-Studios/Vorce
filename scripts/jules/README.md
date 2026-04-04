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
- `run-master-issue-cycle.ps1`: Liest alle Issue-Paare aus einem Master-Issue und startet die komplette Kette automatisch
- `set-managed-issue-state.ps1`: Schreibt den finalen Status, Managed-Block und optional GitHub-Project-Felder fuer ein Issue, ohne es manuell zu schliessen
- `sync-project-manager.ps1`: Synchronisiert alle relevanten Issues auf einen kompakten, verlaesslichen `Vorce Project Manager`-Block

## Beispiele

```powershell
./scripts/jules/create-jules-session.ps1 -IssueNumber 123 -AutoCreatePr
./scripts/jules/create-jules-session.ps1 -Prompt "Refactor the OSC routing layer" -Repository Vorce-Studios/Vorce
./scripts/jules/monitor-jules-sessions.ps1 -OnlyActive -IncludeActivities
./scripts/jules/monitor-jules-sessions.ps1 -IssueNumber 123 -SyncIssueBody
./scripts/jules/respond-jules-session.ps1 -IssueNumber 123 -ApprovePlan
./scripts/jules/respond-jules-session.ps1 -IssueNumber 123 -Message "Bitte nutze die bestehenden UI-Komponenten in crates/vorce-ui."
./scripts/jules/run-master-issue-cycle.ps1 -MasterIssueNumber 1203 -Repository Vorce-Studios/Vorce
./scripts/jules/set-managed-issue-state.ps1 -IssueNumber 1396 -Repository Vorce-Studios/Vorce -Status Done -Agent "Gemini CLI" -RemoteState completed -QueueState closed
./scripts/jules/sync-project-manager.ps1 -Repository Vorce-Studios/Vorce -FailOnAttention
```

## Duplicate-Dispatch-Guard

`create-jules-session.ps1` startet standardmaessig keine neue Jules-Session, wenn fuer dasselbe GitHub-Issue bereits gleichzeitig aktive Jules-Arbeit laeuft. Dadurch soll verhindert werden, dass derselbe Issue mehrfach parallel Geld verbrennt.

- genau eine aktive Session: wird wiederverwendet statt neu erstellt
- mehrere gleichzeitig aktive Sessions fuer dasselbe Issue: neuer Start wird blockiert
- GitHub-Tracking signalisiert noch aktive Arbeit, aber die referenzierte Session ist nicht aufloesbar: neuer Start wird blockiert, bis der Status wieder sauber ist
- nur historische oder bereits abgeschlossene Session-Referenzen blockieren keinen neuen Start
- bewusster manueller Neustart: nur explizit mit `-ForceNewSession`
- Discovery, Chief of Staff und Jules Builder muessen denselben GitHub-Tracking-Status ebenfalls vor jedem Dispatch respektieren; der Guard lebt also nicht nur im Create-Skript

## Orchestrierung Jules -> Gemini

Der definierte Soll-Ablauf fuer ein Implementierungs-/Verify-Paar ist zusaetzlich in `scripts/jules/ISSUE_ORCHESTRATION_PROCESS.md` dokumentiert. Dort steht auch, welche Stelle im Wrapper welche Prozessregel umsetzt.

## Jules Naming-Regel fuer PR und Branch

Bei Jules-Issues wird der PR-Titel und der Arbeitsbranch direkt aus dem Issue-Titel abgeleitet:

- PR-Titel: `PR` + Issue-Titel
- Work-Branch: `B-Jules/` + Issue-Titel

Beispiel fuer Issue-Titel `__SI-08_MAI-001_VERIFY_PROTOCOLS_API_AND_EXTERNAL_IDS_V2`:

- PR-Titel: `PR__SI-08_MAI-001_VERIFY_PROTOCOLS_API_AND_EXTERNAL_IDS_V2`
- Work-Branch: `B-Jules/__SI-08_MAI-001_VERIFY_PROTOCOLS_API_AND_EXTERNAL_IDS_V2`

`create-jules-session.ps1` schreibt diese Sollwerte in den Jules-Prompt und in den Session-Kommentar. `run-master-issue-cycle.ps1` prueft spaeter den echten PR-Titel und Branch gegen genau diese Sollwerte.

## GitHub-Issue-Felder

Standard-GitHub-Issues haben per REST API keine frei definierbaren Custom Fields. Die Skripte schreiben deshalb einen verwalteten, bewusst kompakten Block `## Vorce Project Manager` in den Issue-Body und koennen zusaetzlich Kommentare posten. Sichtbar gehalten werden nur die verlaesslichen Kernfelder `Queue State`, `Remote State`, `Work Branch`, `Linked PR` und `Last Update`. Im GitHub-Projekt werden zusaetzlich die getrennten Statusfelder `jules_session_status` und `pr_checks_status` gepflegt.

## Optionale GitHub-Project-V2-Synchronisation

Wenn die Project-Ansicht direkt gepflegt werden soll, koennen dieselben Werte optional in ein GitHub Project V2 geschrieben werden. Dazu muessen mindestens diese Umgebungsvariablen gesetzt sein:

- `VORCE_PROJECT_OWNER`
- `VORCE_PROJECT_NUMBER`

Optional koennen abweichende Feldnamen konfiguriert werden:

- `VORCE_PROJECT_STATUS_FIELD`
- `VORCE_PROJECT_QUEUE_STATE_FIELD`
- `VORCE_PROJECT_JULES_SESSION_STATUS_FIELD`
- `VORCE_PROJECT_PR_CHECKS_STATUS_FIELD`
- `VORCE_PROJECT_WORK_BRANCH_FIELD`
- `VORCE_PROJECT_LAST_UPDATE_FIELD`
- `VORCE_PROJECT_LINKED_PR_FIELD`

Wenn diese Konfiguration fehlt, bleibt der Project-Sync deaktiviert und nur der Issue-Sync wird ausgefuehrt.

