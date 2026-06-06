# Finaler Implementierungsplan: Vorce Autopilot Struktur-Optimierung

Dieses Dokument dient als freigegebener strategischer Entwurf (Blueprint) für zukünftige Refactoring-Arbeiten am Vorce Autopilot System. Die Struktur orientiert sich an der Beibehaltung der bestehenden Verzeichnisse für maximale Stabilität bei Git-Merges, lagert jedoch Prompts aus und führt robuste Hilfsclients ein.

---

## 1. Prompt-Management (Auslagerung in Markdown-Dateien)

Um die Lesbarkeit zu erhöhen und Syntax-Fehler im JSON-Format der Konfiguration zu vermeiden, werden alle System-Prompts aus `autopilot-config.json` und hartkodierte Prompts aus `lib/autopilot-prompts.ps1` in separate Markdown-Dateien ausgelagert.

### Geplante Struktur

Erstellung eines neuen Verzeichnisses `scripts/codex-cli/prompts/` mit folgenden Dateien:

- `prompts/planning_jules_sync.md` (Jules active/stalled check)
- `prompts/planning_pr_sync.md` (PR conflict/CI checks)
- `prompts/planning_analysis.md` (CEO repository compass analysis)
- `prompts/planning_proposal.md` (Issue proposal logic)
- `prompts/planning_synthesis.md` (Synthesis & backlog numbering)
- `prompts/monitor_sessions.md` (Session checks)
- `prompts/monitor_prs.md` (PR validation)
- `prompts/monitor_conflicts.md` (Conflict handling)
- `prompts/monitoring_synthesis.md` (Status evaluation)
- `prompts/audit_consistency.md` (Data audit)
- `prompts/audit_performance.md` (Performance checklist)
- `prompts/audit_synthesis.md` (CEO Beta decision JSON format)

### Implementierung im Code

In `scripts/codex-cli/lib/autopilot-prompts.ps1` wird die Funktion `Get-VorceConfigPrompt` so angepasst, dass sie:

1. Prüft, ob `prompts/$PromptKey.md` existiert.
2. Wenn ja, den Inhalt dieser Datei lädt.
3. Wenn nein, als Fallback die Prompts aus `autopilot-config.json` liest.

---

## 2. API-Kapselung (GitHub & Jules Clients)

Um Code-Duplikation zu reduzieren und robustes Fehler-Handling zu gewährleisten, werden alle direkten Aufrufe an das `gh`-CLI und das Jules-Skript in zwei Bibliotheken gekapselt:

### Neue Datei: `scripts/codex-cli/lib/github-client.ps1`

Exponiert standardisierte Funktionen:

- `Get-GitHubIssues` (ruft `gh issue list` auf und parset JSON)
- `Create-GitHubIssue` (erstellt Issues mit Labels und Fehlerbehandlung)
- `Get-GitHubPullRequests` (lädt offene PRs inklusive Build-Status)
- `Invoke-GitFetchPrune` (führt Fetch & Prune aus)
- `Get-GitGoneBranches` (identifiziert gelöschte Remote-Branches)
- `Delete-GitBranch` (löscht lokale Branches)

### Neue Datei: `scripts/codex-cli/lib/jules-client.ps1`

Dot-sourced das zugrundeliegende `jules-api.ps1` und stellt sichere Wrapper bereit:

- `Start-NewJulesSession` (ruft `create-jules-session.ps1` mit API-Key auf)
- `Get-JulesSessionSafe` (ruft Status ab)
- `Approve-JulesPlanSafe` (bestätigt Pläne automatisch)
- `Send-JulesMessageSafe` (übermittelt Feedback an Jules)
- `Get-AllJulesSessionsSafe` (holt alle aktiven/inaktiven Sitzungen)

### Code-Bereinigung

Die Skripte `planning-wakeup.ps1`, `monitoring-wakeup.ps1` und `audit-wakeup.ps1` werden so modifiziert, dass sie ausschließlich die Funktionen dieser neuen Client-Bibliotheken importieren und nutzen.

---

## 3. Prozesssicherheit & PID-Tracking

Zur Vermeidung von verwaisten Prozessen (wie unkontrolliert weiterlaufenden Vite- oder Node-Prozessen) wird ein deterministisches PID-Tracking eingeführt:

### PID-Datei

Beim Starten der Suite in `Start-Autopilot.ps1` werden die Prozess-IDs (PIDs) der gestarteten Instanzen (Vite, Sync-Skript, Autopilot-Schleife) in der Datei `var/run/autopilot-pids.json` gespeichert.

### Beenden-Logik

In der Funktion `Stop-AutopilotSuiteProcesses`:

1. Die Datei `var/run/autopilot-pids.json` wird ausgelesen.
2. Alle dort verzeichneten Prozesse werden gezielt mittels `Stop-Process -Id $pid -Force` beendet.
3. Die PID-Datei wird gelöscht.
4. Als Fallback bleibt das bestehende CommandLine-Regex-Matching aktiv, um evtl. manuell gestartete Prozesse aufzuräumen.

### Deliberation Cleanup

In `scripts/codex-cli/lib/deliberation-engine.ps1` wird die Ausführung der sichtbaren Phasen in einen `try/finally`-Block gebettet, um die lokalen Argument- und Status-Dateien (`ceo-args-*.json`, `ceo-output-*.txt`) im `finally`-Block sofort zu löschen, anstatt sie bis zum nächsten Hauptschleifen-Durchlauf liegenzulassen.

---

## 4. Verifikationsplan

Falls dieser Entwurf zu einem späteren Zeitpunkt umgesetzt werden soll, sieht der Verifikationsplan wie folgt aus:

1. **Automatisierte Smoke-Checks:**
   Ausführen des bestehenden Regressionstests:

   ```powershell
   .\scripts\codex-cli\test-autopilot-regression.ps1
   ```

2. **Plattform-Kompatibilität:**
   Starten des Autopiloten im DryRun-Modus:

   ```powershell
   .\scripts\codex-cli\Start-Autopilot.ps1 -DryRun -PlanOnce
   ```

   Überprüfen, ob die Markdown-Prompts sauber eingelesen werden und keine Pfade ins Leere laufen.
3. **Prozesssicherheit:**
   Beenden des Autopiloten und Überprüfung, ob `var/run/autopilot-pids.json` gelöscht wurde und keine verwaisten Node/Vite-Prozesse auf Port 5173 lauschen.
