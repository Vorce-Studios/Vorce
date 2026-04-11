# 🚀 Jules AI Integration & Setup Guide

> **Zentrale Dokumentation für die Jules CI/CD Integration, Automation und Session-Management im Vorce-Projekt.**

---

## 📋 System-Überblick

Die Jules-Integration ermöglicht es, Entwicklungsaufgaben automatisch von einem KI-Agenten bearbeiten zu lassen. Der komplette Workflow umfasst:

1. **Issue-Generierung** (basierend auf GitHub Project / Roadmap)
2. **Jules-Verarbeitung** der Issues (Remote Sessions)
3. **Automatisches Monitoring** & Eskalation (Ben's Logik)
4. **Automatisches Testing** der PRs (CI/CD)
5. **Auto-Merge** bei erfolgreichen Tests
6. **Dokumentations-Updates** (Changelog) nach dem Merge

---

## 🛠️ Setup-Anleitung

### 1. GitHub Labels Konfigurieren
Stelle sicher, dass alle benötigten Labels im Repository vorhanden sind:
```bash
gh label sync --file .github/labels.yml
```
**Wichtigste Labels:**
- `jules-task`: Markiert Issues für Jules
- `jules-pr`: Markiert PRs von Jules
- `status: blocked`: Wird bei hängenden Sessions gesetzt (Eskalation)
- `priority: critical/high/medium/low`

### 2. Jules API Konfiguration
Es gibt zwei empfohlene Wege, Jules zu aktivieren:

#### A. Jules GitHub App (Einfachste Lösung) ⭐
- Installiere die [Jules GitHub App](https://github.com/apps/jules).
- Erlaube Zugriff auf das Vorce-Repository.
- Jules überwacht automatisch Issues mit dem Label `jules-task`.

#### B. Jules API mit GitHub Actions (Vollständige Kontrolle)
- API-Key auf [jules.google.com](https://jules.google.com) generieren.
- Als Repository Secret `JULES_API_KEY` hinterlegen.
- Workflow `.github/workflows/CI-04_session-trigger.yml` nutzen.

### 3. Branch Protection (main)
- **Require status checks to pass:** CI/CD Pipeline, Code Quality, Security Audit.
- **Require branches to be up to date.**
- **Allow force pushes:** Deaktiviert.

---

## 🔄 Operativer Workflow

### 1. Session-Erstellung
- **Automatisch:** Ein Issue erhält das Label `jules-task` → Session wird getriggert.
- **Manuell:**
  ```bash
  gh workflow run CI-04_session-trigger.yml -f issue_number=123
  ```

### 2. Monitoring & Eskalation (Ben)
Der Agent "Ben" überwacht hängende Sessions in `AWAITING_USER_FEEDBACK`.

| Intervall | Wartezeit | Aktion |
|-----------|-----------|--------|
| 1 | 1-6h | Sendet "Continue with the task." an Jules |
| 2 | 6-24h | Erneut "Continue" an Jules |
| 3 | 24-48h | Erstellt GitHub Kommentar, taggt @MrLongNight, setzt `status: blocked` |
| >48h | >48h | Manuelle Intervention / Session Pause |

**Tool:** `scripts/jules/escalate-jules-sessions.ps1`
**Log:** `.Jules/session-monitor-log.md`
**Instructions:** `.agent/BEN.md` (Ben's Role-Definition)

### 3. PR Automation & Auto-Merge
PRs von Jules werden automatisch gemerged, wenn:
- ✅ Alle CI-Checks bestanden sind.
- ✅ Keine Merge-Konflikte vorliegen.
- ✅ Kein "Changes Requested" Review existiert.
- ✅ PR hat das Label `jules-pr`.

---

## 🔍 Monitoring & Debugging

### Status-Checks
```bash
# Aktuelle Sessions überwachen
./scripts/jules/monitor-jules-sessions.ps1 -OnlyActive

# Eskalations-Run manuell starten
./scripts/jules/escalate-jules-sessions.ps1 -Repository "owner/repo"

# PR Status prüfen
gh pr list --label "jules-pr"
```

### Häufige Probleme
- **CI schlägt fehl:** Logs in GitHub Actions prüfen, lokal mit `cargo test` reproduzieren.
- **Auto-Merge blockiert:** Prüfen ob Labels korrekt gesetzt sind und alle Checks grün sind.
- **Session hängt:** Ben's Eskalations-Log in `.Jules/session-monitor-log.md` prüfen.

---

## 🔐 Sicherheit & Permissions
Actions benötigen folgende Permissions:
- `contents: write`, `issues: write`, `pull-requests: write`, `checks: read`.
- **Keine Secrets im Code committen!**

---

**Letztes Update:** 2026-04-11
**Version:** 1.1 (Konsolidiert)
**Status:** Produktionsbereit
