# Jules Session Monitoring System

**Auftraggeber:** John (CEO)
**Verantwortlich:** Ben (COO/Delivery Operator)
**Priorität:** HIGH
**Status:** 🟡 IN PROGRESS

---

## 📋 Task-Beschreibung

Ben, du bist ab sofort verantwortlich für das **Monitoring aller Jules Sessions**.

### Problem
Mehrere Jules Sessions hängen in `AWAITING_USER_FEEDBACK` ohne dass jemand eingreift:
- Session 13411283997285618232: Guardian - Intervall 2/3
- Session 11217710755568478899: Palette - Intervall 1/3
- Weitere Sessions ohne Eskalation

### Deine Verantwortung

1. **Session-Monitoring aufsetzen**
   - Alle offenen Issues mit Label `jules-task` überwachen
   - Session-Status via Jules API prüfen
   - Bei `AWAITING_USER_FEEDBACK` Eskalations-Logik anwenden

2. **Eskalations-Matrix implementieren**

| Intervall | Wartezeit | Aktion |
|-----------|-----------|--------|
| 1 | 1-6h | Sende "Continue with task" an Session |
| 2 | 6-24h | Erneut "Continue" + GitHub Kommentar |
| 3 | 24-48h | Eskaliere an @MrLongNight + Label "status: blocked" |
| >3 | >48h | Pausiere Session + markiere Issue als blocked |

3. **Tools die du nutzen sollst**
   - `scripts/jules/jules-api.ps1` - Session-Status-Checks
   - `scripts/jules/jules-github.ps1` - GitHub Issue-Updates
   - Paperclip MCP `list_issues` - Offene jules-task Issues finden
   - Paperclip MCP `get_issue` - Issue-Details prüfen

### Deliverables

- [ ] PowerShell-Script für Session-Monitoring (`scripts/jules/session-monitor.ps1`)
- [ ] Eskalations-Logik implementiert (Intervall 1-3)
- [ ] GitHub Issue Auto-Update bei Eskalation
- [ ] Dokumentation im `.Jules/` Verzeichnis
- [ ] Test-Run mit bestehenden hängenden Sessions

### Akzeptanzkriterien

- ✅ Keine Session hängt länger als 24h ohne Eskalation
- ✅ @MrLongNight wird bei Intervall 3+ erwähnt
- ✅ Session-Status wird in GitHub Issues aktualisiert
- ✅ Script läuft automatisiert (z.B. via Cron/Task Scheduler)

### Deadline
**Bis zum nächsten Heartbeat** - Das ist kritisch für den Projektfortschritt!

### Eskalation
Wenn du blockiert bist oder unsicher: Eskaliere an mich (John) via Paperclip Comment.

---

**Delegiert von:** John (CEO)
**Datum:** 2026-04-11
**Begründung:** Jules Sessions hängen ohne Eskalation → Blockiert Projektfortschritt → Muss sofort gefixt werden
