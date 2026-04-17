# 🍀 Wee-Orchestrator: Master Workflow (Jules & Maestro Integration)

Dieser Workflow steuert die automatisierte Entwicklung von der Issue-Erkennung bis zum Auto-Merge, unter Verwendung der Maestro-Spezialagenten und Jules-Rollen.

## 🔄 Der Kern-Prozess ("The Loop")

### 1. Issue-Disposition
- **Agent:** `jules_disponent`
- **Aktion:** Nutzt `scripts/jules/create-jules-session.ps1`, um neue `jules-task` Issues an Jules zu senden.
- **Doku:** Verknüpft Session mit GitHub Issue via `jules-github.ps1`.

### 2. Monitoring (Jules & Sessions)
- **Agent:** `jules_tracker`
- **Aktion:** Überwacht laufende Jules-Sessions via `scripts/jules/monitor-jules-sessions.ps1`.
- **Status-Relay:** Aktualisiert Issue-Statusfelder (Labels, Meilensteine) via `set-managed-issue-state.ps1`.

### 3. PR & Branch Management
- **Agent:** `pr_branch_manager`
- **Aktion:** Überwacht PR-Erstellung und führt Checks durch. Nutzt `jules-github.ps1` für `Upsert-JulesIssueTrackingBlock`.
- **CI-Analyse:** Identifiziert CI-Fehler und leitet Korrekturen an `jules` weiter.

### 4. Code Review & Bug-Analyse
- **Agent:** `reviewer` (Gwen / Codex CLI)
- **Trigger:** Sobald ein PR zur Prüfung bereit ist oder komplexe Bugs auftreten.
- **Aktion:** Reviewt den Diff und postet Kommentare direkt in den PR.

### 5. Qualitätssicherung (Testing)
- **Agent:** `jules_guardian`
- **Aktion:** Führt `scripts/jules/pre-pr-checks.sh` aus und validiert die Rust-spezifischen Anforderungen.

### 6. Dokumentations-Abschluss
- **Agent:** `jules_scribe`
- **Trigger:** Nach erfolgreichem PR-Merge.
- **Aktion:** Synchronisiert `CHANGELOG.md` und `ROADMAP.md` (via `sync-project-manager.ps1`).

### 7. Repository-Hygiene
- **Agent:** `jules_archivist`
- **Aktion:** Führt regelmäßige Cleanup-Scans gemäß `.Jules/roles/archivist-repository-manager.md` durch.

---

## 🛠️ Technische Details

- **Source of Truth:** GitHub Issues sind die primäre Datenquelle.
- **CLI-Tools:** Alle Agenten nutzen die lokal installierten CLIs (gh, jules, cargo, gwen, codex).
- **YOLO-Mode:** Agenten arbeiten uneingeschränkt im Projektkontext für maximale Effizienz.
- **Status-Reporting:** Lückenlose Doku wird durch die konsequente Nutzung von `jules-github.ps1` in allen Phasen sichergestellt.
