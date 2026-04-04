# DOC-C5: Vorce-Studios Paperclip Control Plane

Stand: 2026-04-04

## Zweck

`Vorce-Studios` ist die lokale Paperclip-Control-Plane fuer `Vorce`.
Sie ist bewusst kein 24/7-Daemon ohne Aufsicht, sondern ein manuell
startbarer Betriebsmodus, der:

- offene GitHub-Issues analysiert, priorisiert und fuer die Abarbeitung vorbereitet
- Arbeit dynamisch an Jules, Gemini, Qwen, Codex, Copilot oder Antigravity routet
- GitHub als fachlichen Source-of-Truth beibehlt
- Review-, Approval- und UI-Gates vorbereitet
- den CEO entlastet, indem Vorarbeit an Subagents ausgelagert wird
- AFK-Betrieb ueber Telegram vorbereiten kann, ohne dir die wichtigen Entscheidungen zu entziehen

Diese Doku beschreibt den tatsaechlich implementierten Stand, die bewusst
offenen Punkte und den empfohlenen Betrieb.

---

## Status auf einen Blick

### Was jetzt funktioniert

- lokale Paperclip-Company `Vorce-Studios`
- manuelles Starten, Health-Check, Drain-and-Stop
- Planning-first Betrieb statt blindem Abarbeiten
- GitHub-first Sync fuer Orchestrierungsstatus in:
  - GitHub-Issue-Block
  - gemanagte Labels
  - Project-V2-Felder
- `paperclip-plugin-github-issues` installiert, gepatcht und aktiv
- bidirektionale Paperclip <-> GitHub-Issue-Verlinkung
- AFK-Modus mit lokalem Toggle und Telegram-Transportvorbereitung
- `paperclip-plugin-telegram` installiert
- Supervisor-Heartbeat fuer AFK-Kurzmeldungen vorbereitet

### Was absichtlich noch nicht vollautonom ist

- Telegram-basierte Freigaben senden noch nichts, solange keine Bot-/Chat-Credentials gesetzt sind
- grosse Architektur-, Release- und UI-Entscheidungen bleiben Human-Gates
- Review-/Merge-Governance ist risikobasiert, aber weiterhin bewusst konservativ
- Antigravity ist aktuell Worker-/Tool-Host, nicht eigener Paperclip-Kernadapter

### Wichtigste aktuelle Wahrheit

GitHub ist jetzt wieder der fachliche Source-of-Truth.

Das bedeutet in der Praxis:

- GitHub-Issues bleiben der zentrale Ort fuer Aufgabe, Fortschritt, Genehmigungsbedarf und sichtbaren Orchestrierungsstatus
- Paperclip haelt den operativen Laufzeitkontext, Agentenstatus und interne Link-State-Daten
- die fuer dich wichtigen Orchestrierungsdaten werden dauerhaft nach GitHub zurueckgespiegelt
- neue Jules-Sessions duerfen nicht mehr blind neu erzeugt werden; blockiert wird nur bei gleichzeitig aktiver Jules-Arbeit oder wenn GitHub selbst noch einen aktiven Lauf signalisiert

---

## Betriebsmodell

### Deployment-Modell

- Company: `Vorce-Studios`
- Project: `Vorce Release Train`
- GitHub Project V2 Target: `Vorce-Studios#1` mit Titel `@Vorce Project Manager`
- Deployment Mode: `local_trusted`
- API: `http://127.0.0.1:3140`
- kein Windows-Autostart
- Start nur manuell auf Wunsch

### Startverhalten

Beim Start passiert nicht einfach nur "Server hochfahren", sondern:

1. Paperclip-Worktree und Runtime werden validiert.
2. Company, Agenten und Project werden sichergestellt.
3. GitHub-Labels und Project-Felder werden sichergestellt.
4. Vendor-Plugins werden installiert oder refreshed.
5. GitHub-Planning-Sweep wird ausgefuehrt.
6. GitHub-Pull-Sync wird angestossen.
7. Supervisor startet und uebernimmt den laufenden Betrieb.

### Stopverhalten

Es gibt zwei Beendigungsarten:

- normaler Stop:
  beendet Paperclip und Supervisor
- `FinishCurrentWorkOnly`:
  setzt die Runtime auf `draining`, nimmt keine neue Discovery-Arbeit mehr an
  und beendet danach die Instanz sauber

---

## Wichtige Skripte

### Kernbetrieb

- `scripts/paperclip/Initialize-Vorce-Studios.ps1`
- `scripts/paperclip/Start-Vorce-Studios.ps1`
- `scripts/paperclip/Stop-Vorce-Studios.ps1`
- `scripts/paperclip/Get-Vorce-StudiosHealth.ps1`
- `scripts/paperclip/Invoke-Vorce-StudiosSupervisor.ps1`
- `scripts/paperclip/Sync-Vorce-StudiosGitHubState.ps1`
- `scripts/paperclip/Invoke-Vorce-StudiosPlanningSweep.ps1`

### AFK / Telegram

- `scripts/paperclip/Set-Vorce-StudiosTelegramConfig.ps1`
- `scripts/paperclip/Enable-Vorce-StudiosAfkMode.ps1`
- `scripts/paperclip/Disable-Vorce-StudiosAfkMode.ps1`
- `scripts/paperclip/Get-Vorce-StudiosAfkMode.ps1`

### Agentenlaufzeit

- `scripts/paperclip/Invoke-Vorce-StudiosAgent.ps1`

---

## Agentenmodell

### CEO / Chief Architect

- primaer Codex
- entscheidet Priorisierung, Grenzfaelle, Architektur, Release-Fragen und Eskalationen
- arbeitet `delegation-first`
- zieht keine grossen Rohlogs oder Diffs, wenn eine Subagent-Zusammenfassung ausreicht

### Chief of Staff / Capacity Router

- verwaltet Queue, Toolverfuegbarkeit und Failover
- entlastet den CEO von operativer Kleinarbeit
- waehlt je Task den passenden Executor

### Discovery Scout

- analysiert offene GitHub-Issues
- fuehrt Planning und Priorisierung aus
- erkennt zusaetzlichen Handlungsbedarf aus Labels, Status und Projektzustand
- importiert oder aktualisiert keine Arbeit blind, sondern leitet aus dem GitHub-Tracking vor dem Dispatch einen Barrier-Status ab:
  `done`, `in_review`, `in_progress`, `blocked`, `backlog` oder `dispatchable`

### Jules Builder

- primaerer Low-Cost-Builder
- uebernimmt Sessions, reagiert auf Session-Zustaende und PR-Erzeugung
- erstellt keine neue Session, wenn fuer dasselbe Issue bereits aktive Jules-Arbeit erkannt wird; historische Session-Referenzen allein sind kein Dauer-Blocker
- respektiert denselben GitHub-Barrier-Status auch unmittelbar vor dem Jules-Start, damit geschlossene Issues, offene PRs und Attention-Faelle nicht erneut dispatcht werden

### Review Pool

- `Gemini Reviewer`: Standardpfad
- `Qwen Reviewer`: Fallback
- `Codex Reviewer`: High-Risk, Architektur, harte Bugs

### Ops / Merge Steward

- wertet Checks und Gates aus
- bereitet Merge-Entscheidungen vor
- spiegelt Status sauber nach GitHub

### Atlas Context Agent

- optionale Kontextschicht
- nutzt lokale Atlas-Artefakte fuer Repo-Verstaendnis und Vorarbeit

---

## Planning-First Betrieb

### Warum das wichtig ist

`Vorce-Studios` soll nicht stumpf "offene Issues nacheinander" abarbeiten.
Vor jedem produktiven Lauf wird deshalb zuerst geplant und priorisiert.

### Wie es aktuell funktioniert

Der Planning-Sweep:

- liest offene GitHub-Issues
- bewertet Prioritaet ueber Labels, Projektstatus und Heuristiken
- ordnet jedes Issue in Buckets ein:
  - `critical`
  - `high`
  - `medium`
  - `low`
- bestimmt die aktuelle Readiness:
  - `ready`
  - `active`
  - `in_review`
  - `awaiting_ui_test`
  - `awaiting_user_approval`
  - `blocked`

### Aktuelle Quellen fuer das Planning

- GitHub Labels
- GitHub Project-Status
- Issue-Titelmuster
- vorhandene Managed-Labels

### Persistenz

Der Planning-Sweep schreibt nach:

- `.paperclip-home/runtime/vorce-studios/planning-snapshot.json`

und wird verwendet fuer:

- Priorisierungsuebersicht
- GitHub-Issue-Tracking-Block
- Project-V2-Beschreibung/Prioritaetsfelder

---

## GitHub als Source-of-Truth

### Ziel

GitHub bleibt der zentrale Ort fuer die fuer dich sichtbaren und relevanten
Zustaende.

### Praktische Aufteilung

GitHub enthaelt:

- fachliche Aufgabenbeschreibung
- sichtbaren Orchestrierungsstatus
- Approval-/UI-Gate-Hinweise
- PR-Bezug
- Review-Zustand
- Planning-Zusammenfassung
- Project-V2-Felder

Paperclip enthaelt:

- Agenten, Company, Project
- internen Laufzeitkontext
- Plugin-State
- interne Link-Metadaten
- Supervisor-/Process-State

Wichtig:

Paperclip ist nicht mehr der alleinige Traeger wichtiger Orchestrierungsdaten.
Die wesentlichen Signale werden nach GitHub gespiegelt.

---

## Feste Mapping-Regeln Paperclip -> GitHub

### 1. GitHub-Issue-Block

Jedes verknuepfte GitHub-Issue erhaelt oder aktualisiert einen Block
zwischen:

- `<!-- jules-session:begin -->`
- `<!-- jules-session:end -->`

Dieser Block enthaelt sowohl Hidden-Comments als maschinenlesbare Schicht
als auch die sichtbare Sektion `## Vorce Project Manager`.

### Hidden-Comment Mapping

| Feld | GitHub Key |
| --- | --- |
| Paperclip Issue ID | `vorce-paperclip-issue-id` |
| Paperclip Issue Key | `vorce-paperclip-issue-key` |
| Orchestration Status | `vorce-orchestration-status` |
| Review Status | `vorce-review-status` |
| Human Gate | `vorce-human-gate` |
| Approval ID | `vorce-approval-id` |
| Approval Status | `vorce-approval-status` |
| Executor | `vorce-executor` |
| Planner Score | `vorce-planner-score` |
| Planner Bucket | `vorce-planner-bucket` |
| Planner Updated | `vorce-planner-updated` |
| Queue State | `vorce-queue-state` |
| Remote State | `vorce-remote-state` |
| Work Branch | `vorce-work-branch` |
| Last Update | `vorce-last-update` |

### Sichtbarer Tracking-Block

Im sichtbaren Bereich werden mindestens diese Felder gepflegt:

- Queue State
- Remote State
- Orchestration Status
- Work Branch
- Linked PR
- Current Executor
- Review Status
- Human Gate
- Approval
- Planning
- Last Update

### 2. Managed Labels

Die Control Plane behandelt diese Labels als gemanagt:

- `sync: paperclip`
- `status: in-progress`
- `status: blocked`
- `status: needs-review`
- `status: needs-testing`
- `status: ready-to-merge`
- `gate: approval`
- `gate: ui-test`
- `review: passed`
- `review: changes-requested`

Die Labels werden nicht nur gesetzt, sondern bei Statuswechseln auch
aktiv aufgeraeumt.

### 3. Project-V2-Felder

Die Control Plane pflegt zusaetzlich Project-V2-Felder.
Verwendet werden aktuell insbesondere:

Wichtig:

- Ziel ist das Organisationsprojekt `Vorce-Studios#1`
- das schreibbare PR-Feld ist `Linked PR`
- das GitHub-Built-in `Linked pull requests` wird bewusst nicht direkt beschrieben,
  weil dieses Feld von GitHub speziell behandelt wird und nicht wie ein normales
  Textfeld aktualisiert werden kann

| Feld | Bedeutung |
| --- | --- |
| `Queue State` | Queue-/Dispatch-Sicht |
| `jules_session_status` | Jules-Session-Zustand |
| `pr_checks_status` | Check-Zustand |
| `review_status` | AI-/Manueller Review-Zustand |
| `human_gate` | erforderliches Human-Gate |
| `paperclip_issue` | Paperclip-Issue-Key |
| `agent` | aktuell bevorzugter oder aktiver Executor |
| `sub_agent` | Rolle wie `coder`, `tester`, `architect`, `code_reviewer` |
| `permit_issue` | Approval-Abbildung |
| `task_type` | Feature / Fix / Refactor / Test |
| `priority` | vereinfachte A/B/C-Prioritaet |
| `description` | Planning-Zusammenfassung |
| `task_id` | Paperclip-Issue-Key |
| `area` | grobe Komponentenzuordnung |
| `Linked PR` | schreibbare PR-Referenz fuer Operator-Sicht |

### 4. Link-State Paperclip <-> GitHub

Der offizielle Plugin-Pfad `paperclip-plugin-github-issues` ist aktiv und
legt pro verknuepftem Issue einen bidirektionalen Link-State in Paperclip an.

Dieser Link-State wird genutzt fuer:

- statusbezogene Synchronisation
- Kommentar-Bridging
- Webhook-/Poll-gestuetztes Catch-up

---

## Sync-Architektur

### A. Repo-eigene GitHub-First Sync-Schicht

Datei:

- `scripts/paperclip/lib/GitHubOrchestrationSync.ps1`

Aufgaben:

- Planning-Snapshot
- Tracking-Block in GitHub-Issues
- Managed Labels
- Project-V2-Felder
- Approval-/Gate-/Executor-Spiegelung

Dieser Pfad ist aktuell der wichtigste Mechanismus, um GitHub als sichtbaren
Source-of-Truth zu behandeln.

Technisch bedeutet das:

- GitHub-Issue-Block und Labels werden direkt gepflegt
- Project-V2-Felder werden gegen `Vorce-Studios#1` geschrieben
- `paperclip-plugin-github-issues` haelt den bidirektionalen Issue-Link-State
- wenn GitHub GraphQL limitiert ist, bleiben Issue-Block und Labels weiterhin
  aktuell; Project-V2-Felder laufen dann verzögert nach

### B. Offizielles Plugin `paperclip-plugin-github-issues`

Status:

- installiert
- aktiviert
- periodischer Sync laeuft
- bidirektionale Links werden erfolgreich backfilled

Der Plugin-Worker:

- pollt periodisch
- liest verknuepfte GitHub-Issues
- synchronisiert Status und optional Kommentare
- verarbeitet GitHub-Webhooks, wenn sie konfiguriert werden

### C. Zusammenspiel beider Ebenen

Die Rollen sind bewusst getrennt:

- repo-eigene Sync-Schicht:
  sichtbare Vorce-Orchestrierung in GitHub
- Plugin:
  generischer Paperclip <-> GitHub Link-State und Connector-Funktion

So bleibt der Vorce-spezifische Status explizit und nachvollziehbar, waehrend
das Plugin die generische Issue-Verknuepfung uebernimmt.

---

## Vendor-Plugin-Fix fuer GitHub Issues

### Warum ein Patch noetig war

Das offizielle Plugin war lokal installierbar, aber der periodische Sync war
im Vorce-Setup anfangs nicht funktionsfaehig.

Die wesentlichen Probleme waren:

- fehlende/inkonsistente Faehigkeiten im Vendor-Manifest
- fehlerhafte Nutzung von `ctx.state.set(...)` im Plugin-Code

### Was Vorce-Studios jetzt automatisch macht

Die Datei:

- `scripts/paperclip/lib/PaperclipPlugins.ps1`

enthaelt jetzt Vendor-Overrides fuer
`paperclip-plugin-github-issues`.

Diese Overrides werden beim Sicherstellen der Plugin-Quelle automatisch
angewendet, bevor das Plugin installiert oder refreshed wird.

### Warum das wichtig ist

Die Fixes leben damit nicht nur fluechtig in `.paperclip-home`, sondern sind
ueber die repo-versionierte Bootstrap-Logik reproduzierbar.

---

## Telegram und AFK-Modus

### Aktueller Zustand

`paperclip-plugin-telegram` ist installiert, aber derzeit deaktiviert,
weil noch keine Telegram-Credentials gesetzt sind.

### AFK-Zielbild

Wenn AFK aktiv ist, soll Vorce-Studios:

- Approval-Anfragen bevorzugt ueber Telegram ausspielen
- sehr kurze Heartbeat-Nachrichten senden
- dich ueber laufende Arbeit und Blocker knapp auf dem Laufenden halten

### Was heute schon implementiert ist

- AFK-Statusdatei
- Toggle-Skripte fuer an/aus
- bevorzugter Approval-Kanal `telegram`, solange Telegram wirklich bereit ist
- Fallback auf `paperclip`, wenn Telegram nicht bereit ist
- Kurz-Heartbeat ueber Supervisor

### Heartbeat-Inhalt

Die AFK-Nachricht ist absichtlich kurz und sieht inhaltlich so aus:

- aktueller Fokus
- Anzahl blockierter Themen
- Anzahl offener Todo-Themen

Keine langen Zusammenfassungen, kein Spam.

### Aktivierung

1. Telegram konfigurieren:

```powershell
.\scripts\paperclip\Set-Vorce-StudiosTelegramConfig.ps1 `
  -BotToken "<bot-token>" `
  -DefaultChatId "<chat-id>" `
  -ApprovalsChatId "<chat-id>" `
  -EnableAfkMode
```

2. AFK explizit aktivieren:

```powershell
.\scripts\paperclip\Enable-Vorce-StudiosAfkMode.ps1
```

3. Status pruefen:

```powershell
.\scripts\paperclip\Get-Vorce-StudiosAfkMode.ps1
```

4. AFK wieder deaktivieren:

```powershell
.\scripts\paperclip\Disable-Vorce-StudiosAfkMode.ps1
```

### Aktuelle Fallback-Regel

- AFK aktiv + Telegram bereit -> Approval-Kanal `telegram`
- sonst -> Approval-Kanal `paperclip`

---

## Supervisor und Zyklen

### Tick

Der Supervisor laeuft alle 30 Sekunden.

### Agent-Intervalle

Aktuell:

- Chief of Staff: 60s
- Jules Builder: 60s
- Review Pool: 120s
- Ops: 90s
- Discovery: 900s
- CEO: 600s

### Maintenance

- GitHub-Sync: alle 300 Sekunden
- GitHub-Plugin Periodic Sync: alle 15 Minuten

### AFK-Heartbeat

Der Heartbeat wird im Supervisor nach jedem Zyklus geprueft und nur gesendet,
wenn:

- AFK aktiv ist
- Telegram bereit ist
- das Heartbeat-Fenster erreicht ist
- oder sich der Digest seit der letzten Nachricht relevant geaendert hat

---

## Review- und Governance-Regeln

### Human-Gates bleiben verpflichtend fuer

- Architekturwechsel
- neue Dependencies
- CI-/Branch-Protection-Aenderungen
- Release-Candidate-Merges
- Persistenz-/Kompatibilitaetsaenderungen
- sichtbare UI-Abnahmen
- unklare High-Risk-Faelle

### Automatisierte Labels und Stati helfen hier

Beispiele:

- `gate: approval`
- `gate: ui-test`
- `review: passed`
- `review: changes-requested`

Damit ist in GitHub sichtbar, warum etwas steht und welcher Schritt als
naechstes gebraucht wird.

---

## Bedienung im Alltag

### Typischer Start

```powershell
.\scripts\paperclip\Start-Vorce-Studios.ps1
```

### Zustand pruefen

```powershell
.\scripts\paperclip\Get-Vorce-StudiosHealth.ps1
```

Wichtige Felder im Health-Output:

- `runtimeMode`
- `sync.sourceOfTruth`
- `sync.githubPlugin.status`
- `sync.telegramPlugin.status`
- `afkMode.effectiveApprovalChannel`
- `capacity`

### Sofortiger GitHub-Sync

```powershell
.\scripts\paperclip\Sync-Vorce-StudiosGitHubState.ps1
```

### Planning aktualisieren

```powershell
.\scripts\paperclip\Invoke-Vorce-StudiosPlanningSweep.ps1
```

### Geordnet stoppen

```powershell
.\scripts\paperclip\Stop-Vorce-Studios.ps1 -FinishCurrentWorkOnly
```

---

## Bekannte Grenzen

### Telegram

Ohne Bot-Token und Chat-IDs bleibt das Telegram-Plugin absichtlich deaktiviert.

### GitHub GraphQL Rate Limits

Project-V2-Feldsync benoetigt GraphQL.
Wenn GitHub das GraphQL-Limit erreicht, gilt aktuell:

- GitHub-Issue-Block und Labels syncen weiter
- Project-V2-Felder laufen spaeter nach
- der Supervisor versucht den Sync in spaeteren Zyklen erneut
- punktuelle Feldtests oder gezielte Einzelsyncs sind dann oft sinnvoller als
  sofortige Vollsyncs

### Planning-Heuristik

Die Priorisierung ist bereits nuetzlich, aber noch stark label- und
statusgetrieben. Die Heuristik ist noch nicht auf echte Release-Trains,
Abhaengigkeiten zwischen Issues und Regression-Cluster optimiert.

### Merge-Governance

Die Sync- und Gate-Schicht ist da, aber ein komplett harter
"merge nur ueber zentrale Governance-Automation"-Pfad ist noch nicht fertig.

### Antigravity

Aktuell als Tool-/Execution-Option behandelt, nicht als tiefer Paperclip-Adapter.

---

## Troubleshooting

### GitHub-Plugin ist `disabled` oder `error`

Pruefen:

- `.\scripts\paperclip\Get-Vorce-StudiosHealth.ps1`
- `.\scripts\paperclip\Start-Vorce-Studios.ps1`

Wenn noetig:

- Vendor-Plugin wird beim Start automatisch refreshed
- der GitHub-Token wird aus `gh auth token` in ein Company-Secret gespiegelt

### Telegram-Plugin bleibt `disabled`

Das ist korrekt, solange in `.paperclip/.env` keine Telegram-Werte gesetzt sind.

### GitHub-Issue zeigt keinen Vorce-Block

Dann ist das Issue entweder:

- noch nicht verknuepft
- noch nicht von der Sync-Schicht erfasst
- oder ausserhalb der aktuellen Discovery-/Orchestrierungslogik

Dann hilft:

```powershell
.\scripts\paperclip\Sync-Vorce-StudiosGitHubState.ps1
```

### Planning-Snapshot wirkt veraltet

Dann explizit neu erzeugen:

```powershell
.\scripts\paperclip\Invoke-Vorce-StudiosPlanningSweep.ps1
```

---

## Empfohlene naechste Verbesserungen

### 1. Telegram produktiv schalten

Sobald Bot-Token und Chat-IDs gesetzt sind, sollte AFK-Betrieb mit echten
Approval-Runden getestet werden.

### 2. Planning weiter verfeinern

Naechster grosser Hebel:

- Issue-Abhaengigkeiten
- Regression-Cluster
- Release-Slices
- "nicht einfach mehr anfangen, sondern sauberer ordnen"

### 3. GitHub-Webhooks fuer das GitHub-Plugin anschliessen

Dann muss weniger ueber Polling abgefangen werden und Statuswechsel kommen
schneller in Paperclip an.

### 4. Health-Output weiter verdichten

Nuetzlich waere ein kompakter Operator-Modus mit:

- Top-5 Planning-Issues
- Pending Approvals
- Telegram-Bereitschaft
- aktueller aktiver Builder

### 5. Telegram-Approval-Commands bewusst eng halten

Empfehlung:

- nur approve / reject / clarify
- keine breit offenen operativen Kommandos
- so bleibt AFK hilfreich, aber nicht chaotisch

### 6. Project-V2 noch staerker als Operator-Board nutzen

Die Felder sind bereits da. Als naechstes lohnt sich:

- klare Views fuer `awaiting approval`
- `awaiting ui test`
- `ready to merge`
- `blocked by tool quota`

---

## Fazit

`Vorce-Studios` ist jetzt keine lose Sammlung von Skripten mehr, sondern eine
lokal betreibbare Control Plane mit:

- Planning-first Arbeitsweise
- GitHub-first Sichtbarkeit
- Paperclip-Orchestrierung
- funktionierendem GitHub-Issue-Link-Sync
- vorbereiteter AFK-/Telegram-Schicht

Der produktive Kern ist einsatzfaehig.
Die groessten offenen Themen sind jetzt nicht mehr "ob es grundsaetzlich
geht", sondern Feinjustierung von Governance, Telegram-Betrieb und
Priorisierungsqualitaet.
