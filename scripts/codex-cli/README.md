# Vorce Autopilot

Der Vorce Autopilot startet Dashboard, Telemetrie-Sync, Autopilot-Loop und geplante Codex-Controller-Sessions fuer den autonomen Issue-/PR-Betrieb.

## Normaler Start

```powershell
.\scripts\codex-cli\Start-Autopilot.ps1
```

Beim normalen Start passiert Folgendes:

1. Bereits laufende Vorce-Autopilot-Prozesse werden beendet.
2. Das Dashboard wird unter `http://localhost:5173` gestartet.
3. Das Startskript startet Vite mit `--host 0.0.0.0` und prueft `http://localhost:5173`, `http://127.0.0.1:5173` und `registry.json` als Dashboard-Health-Check.
4. Der Dashboard-Sync-Service wird gestartet.
5. Der Autopilot-Loop wird in einem separaten sichtbaren PowerShell-Fenster gestartet.
6. Beim Start wird eine sichtbare Codex-Planning-Session erzwungen.

Das Start-Terminal bleibt als Control-Konsole offen.

## Control-Konsole

Die Control-Konsole ist das urspruengliche Terminal, in dem `Start-Autopilot.ps1` gestartet wurde.

Tasten:

- `Q`: komplette Suite beenden.
- `Ctrl+C`: komplette Suite beenden.
- `S`: aktive Suite-Prozesse anzeigen.
- `W`: `autopilot.wakeup` schreiben und den Autopilot-Loop aus dem Sleep holen.

Die Control-Konsole zeigt beim Start eine kompakte State-Zeile mit Session-ID, Heartbeat-Alter, aktiven Delegierungen, Review-Queue und offenen Entscheidungen. Danach gibt es keine periodischen 30-Sekunden-Statusmeldungen mehr; mit `S` kann der Prozessstatus manuell abgefragt werden.

Beim Beenden werden Dashboard, Vite/Node, Dashboard-Sync, Autopilot-Loop, sichtbare Codex-Planning-Fenster und eindeutig zu dieser Suite gehoerende Codex-Prozesse gestoppt.

## Fenster-Modell

Es gibt drei getrennte Prozess-/Fensterrollen:

- Start-/Control-Konsole: bleibt offen und dient zum Stoppen/Status/Triggern.
- Autopilot-Loop: separates PowerShell-Fenster mit Scheduler-, Quota- und Monitoring-Ausgaben.
- Codex-Planning: sichtbares Codex-Terminalfenster, das vom Autopilot-Loop gestartet und kontrolliert wird.
- Codex-Monitoring: separates sichtbares PowerShell/Codex-Terminalfenster mit `codex exec`; nicht interaktiv, beendet sich nach dem Monitoring-Auftrag.

Das Codex-Planning-Fenster ist die interaktive Eingriffsstelle. Du kannst Codex dort unterbrechen oder direkt schreiben. Am Ende der Planning-Session muss Codex die Statusdatei auf `completed` setzen; der Autopilot-Loop erkennt das alle 30 Sekunden und schliesst danach das Codex-Terminalfenster automatisch.

## Planning und Monitoring

Die Intervalle stehen in `autopilot-config.json`:

- `wake_intervals.planning_minutes`
- `wake_intervals.monitoring_minutes`

Default aktuell:

- Planning: 120 Minuten
- Monitoring: 15 Minuten

Der normale Start fuegt dem Autopilot-Loop `-ForcePlanningOnStart` hinzu. Dadurch wird direkt beim Start eine sichtbare Planning-Session ausgefuehrt, auch wenn `last_planning_at` laut `autopilot-state.json` noch nicht faellig waere.

Mit `-NoInitialPlanning` kann dieses Verhalten fuer Sonderfaelle deaktiviert werden:

```powershell
.\scripts\codex-cli\Start-Autopilot.ps1 -NoInitialPlanning
```

Wenn eine Planning-Session gelaufen ist, startet das Monitoring-Intervall erst nach dem Ende dieser Planning-Session. Dadurch wird verhindert, dass direkt nach einer langen sichtbaren Planning-Session sofort eine zusaetzliche Monitoring-Session startet.

Planning-Sessions:

- laufen sichtbar und interaktiv in einem separaten PowerShell/Codex-Terminalfenster
- nutzen `gpt-5.5`
- werden nach der ersten erfolgreichen Session ueber `codex_main_session_id` fortgesetzt
- aktualisieren das gemeinsame Lagebild in `autopilot-tasks.md`
- setzen am Ende `tmp/codex-planning-status.json` auf `completed`
- werden danach vom Autopilot-Loop geschlossen, damit keine alten Codex-Fenster offen bleiben

Monitoring-Sessions:

- laufen nicht interaktiv ueber `codex exec` in einem separaten Terminalfenster
- nutzen `gpt-5.4-mini`
- lesen zuerst `autopilot-tasks.md`
- aktualisieren Status, Blocker und naechste Controller-Schritte

Jules-Wartestatus:

- Das Monitoring prueft nicht nur lokale `active_delegations`, sondern auch live per Jules-API alle Sessions mit `AWAITING_USER_FEEDBACK`.
- Auch nicht lokal getrackte Jules-Sessions werden dadurch gefunden, solange sie zum konfigurierten Repository gehoeren.
- Fuer solche Sessions sendet der Controller eine knappe Fortsetzungsanweisung an Jules: Plan fortsetzen, PR erstellen/aktualisieren und harte Blocker klar melden.
- Pro Jules-Session wird die Anzahl automatischer Feedback-Antworten in `autopilot-state.json:jules_feedback_responses` gespeichert.
- Nach `jules.auto_retry_feedback_max` Antworten wird nicht weiter gespammt, sondern eine Entscheidung in `decisions_pending` erzeugt.
- Pro Monitoring-Zyklus werden maximal `jules.max_feedback_sessions_per_cycle` wartende Jules-Sessions automatisch beantwortet.
- PRs mit Merge-Konflikten werden primaer ueber die CLI-Route `merge_conflict_resolution` geloest. Diese Route bevorzugt Gemini CLI und faellt danach auf weitere CLI-Provider zurueck.
- Nur wenn die CLI-Route explizit `Result: TOO_MANY_CONFLICTS` meldet, wird der alte Konflikt-PR geschlossen, der Branch geloescht und eine frische Jules-Neuimplementierung von der aktuellen Basis gestartet.
- PRs mit roten Checks bekommen primaer einen deduplizierten `@Jules`-Kommentar auf demselben PR, damit Jules den bestehenden Branch nachbessert.
- Nach einem erfolgreichen Merge entscheidet die neue Route `qa_disposition` ueber den Abschluss:
  - `QA_TEST`: Issue bleibt offen, Projektstatus wird auf `QA Test` gesetzt und das Label `status: needs-testing` markiert den manuellen Funktionstest.
  - `DONE`: Issue wird auf `Done` gesetzt und geschlossen.
- `qa_disposition` bevorzugt `codex_orchestrator:monitoring`, damit die Abschlussentscheidung beim Orchestrator bleibt; nur bei fehlender Verfuegbarkeit wird auf weitere Provider zurueckgefallen.
- Wenn Jules unter `jules.max_concurrent_sessions` faellt, kann Monitoring aus `delegation_backlog` neue Issue-Sessions starten. Die Planning-Session fuellt diesen Backlog aus delegierbaren GitHub-Issues.

CLI-Issue-Discovery in der deterministischen Planning-Phase ist standardmaessig deaktiviert (`planning.enable_cli_issue_discovery=false`). Dadurch wird nach der Codex-CEO-Planning-Session nicht zusaetzlich Gemini/Kiro/Cursor als `planning`-Route gestartet. Bei Bedarf kann dieser Zusatzschritt in `autopilot-config.json` wieder aktiviert werden.

Die sichtbare CEO-Planning-Session soll fuer Code-Suche, Dokumentationsanalyse, Log-/Diff-Auswertung, kleine lokale Aenderungen und Reviews gezielt CLI-Provider einsetzen. Codex bleibt fuer Priorisierung, Synthese und Steuerung reserviert; Jules ist fuer groessere Implementierungen gedacht, nicht fuer jede kleine Aufgabe.

Planning und Monitoring sind aktive Arbeitslaeufe:

- Wenn PRs an roten Checks, Reviews oder Merge-Konflikten haengen, reicht ein Statushinweis nicht aus. Der Lauf muss den naechsten konkreten Bearbeitungsschritt starten.
- Kleine, klar begrenzte Aenderungen duerfen und sollen ueber CLI-Provider lokal ausgefuehrt werden, wenn das schneller ist als eine Jules-Session.
- Tokenintensive Repo-Suche, Codeanalyse und Dokumentationsarbeit werden an CLI-Provider delegiert, bevor Codex selbst breite Detailanalyse betreibt.
- Vor spezialisierten Strategie-, Planungs- oder Analyseaufgaben prueft die Planning-Session zuerst die bereits verfuegbaren Skills. Wenn darunter kein guter Treffer ist, soll sie per `find-skills` gezielt nach einem hilfreichen Skill suchen und den passendsten Treffer wirklich anwenden.
- Der Jules-Backlog soll gross genug bleiben, damit freie Slots im Monitoring sofort nachbesetzt werden koennen, aber Aufgaben mit stark ueberlappenden Aenderungsbereichen sollen nicht gleichzeitig laufen.

## Issue-Namen und Hierarchie

Die verbindliche Namenskonvention steht in `autopilot-config.json:issue_naming`:

- Master-Issues enden auf `[MASTER]`.
- Normale, eigenstaendige Issues enden auf `[ISSUE]`.
- Sub-Issues enden auf `[M<Master-Nummer>-S<zweistellige Reihenfolge>]`, zum Beispiel `[M510-S01]`.

Die Reihenfolge eines Sub-Issues kommt primaer aus dem Parent-Issue, sonst aus der aufsteigenden Issue-Nummer. Zusaetzlich zur Suffix-Konvention werden Sub-Issues als echte GitHub-Sub-Issues am Parent verknuepft. Der Text-Hinweis `Part of #<nummer>` im Body bleibt als robuster Fallback erhalten, damit Sync und Dashboard die Hierarchie auch dann erkennen koennen, wenn ein API-Snapshot veraltet ist.

Im Dashboard zeigt die `Issue Overview` nur echte offene GitHub-Issues. Interne Autopilot-Entscheidungen und Jules-Wartehinweise werden dort nicht mehr als Pseudo-Issues eingemischt. Master-Issues lassen sich aufklappen; darunter erscheinen ihre offenen Sub-Issues.

## Gemeinsame Dateien

- `autopilot-state.json`: persistenter Scheduler-/Recovery-State.
- `dashboard/public/active-sessions.json`: Dashboard-State inklusive `scheduler.next_monitoring_at`, `scheduler.next_monitoring_in_seconds`, `scheduler.next_planning_at` und `scheduler.next_planning_in_seconds`.
- `autopilot-tasks.md`: gemeinsames Lagebild zwischen Planning und Monitoring.
- `autopilot-session-lock.md`: verhindert ueberlappende headless/visible Codex-Autopilot-Sessions.
- `autopilot.wakeup`: manuell oder per Control-Konsole erzeugter Wake-Up Trigger.
- `logs/start-autopilot-*.log`: Start- und Control-Konsolen-Logs.
- `tmp/codex-*-prompt.md`: Prompt-Dateien fuer geplante Codex-Sessions.
- `tmp/codex-*-last-message.md`: letzte Antwort headless ausgefuehrter Codex-Sessions.
- `tmp/codex-*-visible.log`: Start-/Exit-Log sichtbarer Codex-Sessions.
- `tmp/codex-*-status.json`: Statusdatei fuer interaktive sichtbare Codex-Sessions. Der Autopilot-Loop prueft diese Datei alle 30 Sekunden.

`tmp/`, `autopilot-session-lock.md`, `autopilot-tasks.md` und `autopilot.wakeup` sind Laufzeitdaten und werden nicht versioniert. Die Dateien werden lokal bei Bedarf automatisch erzeugt.

PR-Worktrees werden nur fuer branch-spezifische Konfliktloesungen verwendet, weil dabei ein anderer PR-Branch gegen `origin/main` gemergt wird. Nach jedem CLI-Konfliktlauf werden sie in einem `finally`-Cleanup entfernt und per `git worktree prune` bereinigt. Normale kleine lokale Aenderungen sollen direkt im Repository erfolgen, zeitnah committed/gepusht werden und nur temporaer von Remote abweichen.

Der Autopilot-Loop schreibt sichtbare Meldungen fuer geplante Codex-Aufrufe, deren Ende und Fehler. Laufende Codex-Planning-Aktivitaet ist im separaten Codex-Terminal sichtbar; die Skriptfenster erzeugen keine periodischen Heartbeat-Ausgaben.

Der im Recovery-Banner angezeigte Wert `Letzter Beat` kommt aus `autopilot-state.json:last_heartbeat`. Er beschreibt den letzten gespeicherten Autopilot-Heartbeat, nicht den Countdown bis zur naechsten Monitoring-Session.

## Optionen

```powershell
.\scripts\codex-cli\Start-Autopilot.ps1 [-DryRun] [-PlanOnce] [-MonitorOnce] [-NoStopExisting] [-NoInitialPlanning] [-NoControlConsole] [-ShowAutopilotWindow] [-HideAutopilotWindow] [-PlanningIntervalOverride <min>] [-MonitoringIntervalOverride <min>]
```

Wichtige Optionen:

- `-NoStopExisting`: beendet bestehende Suite-Prozesse vor dem Start nicht.
- `-NoInitialPlanning`: startet nicht sofort eine sichtbare Planning-Session.
- `-NoControlConsole`: beendet das Startskript nach dem Launch wieder.
- `-HideAutopilotWindow`: versteckt das Autopilot-Loop-PowerShell-Fenster.
- `-PlanOnce`: fuehrt einen einmaligen Planning-Lauf aus.
- `-MonitorOnce`: fuehrt einen einmaligen Monitoring-Lauf aus.

## Fehler-Logging

`Start-Autopilot.ps1` schreibt pro Start eine Logdatei unter:

```text
scripts/codex-cli/logs/start-autopilot-YYYYMMDD-HHMMSS.log
```

Startfehler werden mit Zeilennummer im Terminal und in dieser Logdatei festgehalten. Prozesse, die im fehlgeschlagenen Startversuch bereits erzeugt wurden, werden beim Fehler bereinigt.

## Modell-Konfiguration

Die Codex-Modelle sind aktuell bewusst getrennt:

- Planning: `gpt-5.5`
- Monitoring: `gpt-5.4-mini`

Der alte Modellname `gpt-5-mini` darf nicht verwendet werden, weil er in der aktuellen Codex-Modellliste nicht vorhanden ist.

## Quota-Anzeige

Die Loop-Konsole zeigt keine API-Kosten mehr als primäre Steuerungswerte. Stattdessen werden die Werte angezeigt, die fuer Routing und spaetere dynamische Modellauswahl relevant sind:

- Jules: heutige API-Sessionzahl, aktive Sessions, wartende Sessions, abgeschlossene Sessions.
- Jules trennt dabei jetzt explizit:
  - `calls` / `api_sessions_today`: accountweit per API beobachtete Sessions, die am lokalen Kalendertag neu gestartet wurden.
  - `account_sessions_observed_rolling_24h`: accountweit beobachtete Sessions der letzten 24 Stunden. Diese Kennzahl wird fuer die Jules-Quota-Steuerung verwendet, weil Jules Limits offiziell als Rolling-24h-Fenster beschreibt.
  - `scoped_live_capacity_sessions`: aktuell laufende/queued/planning Sessions nur fuer die konfigurierte Repository-Source.
  - `scoped_live_waiting_sessions`: wartende Sessions mit Feedback-Bedarf nur fuer die konfigurierte Repository-Source.
- Codex: lokale JSONL-Telemetrie, Token-Summe, 5h-Quota und Wochen-Quota aus den Codex-Rate-Limit-Events.
- Gemini: CLI-Quota-Prozentwerte aus dem lokalen Gemini-Quota-Helper plus lokale Token-Telemetrie, sofern vorhanden.
