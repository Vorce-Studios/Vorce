# Paperclip & Agent-Konfiguration — Analyse & Optimierungspotenziale

**Datum:** 2026-04-11
**Autor:** AI-Analyse (korrigiert nach User-Feedback)
**Status:** Entwurf zur Validierung

---

## Validierungs-Update 2026-04-11

Diese Datei war in ihrem ursprünglichen Zustand teilweise spekulativ. Der konkrete Code-Stand im lokalen `paperclip`-Clone wurde inzwischen gegengeprüft.

### Ergebnis der Gegenprüfung

- **Nein, die Datei war nicht vollständig umgesetzt.**
- **Ja, einzelne Teile waren bereits teilweise umgesetzt**, aber nicht vollständig wirksam.
- **Der Hauptgrund für die weiter unübersichtliche `gemini_local`-Ausgabe war ein Parser-Mismatch**:
  - der Adapter verarbeitete überwiegend ältere Event-Formate wie `assistant`, `user`, `tool_call`
  - die aktuellen Gemini-CLI-Runs liefern aber vor allem `init`, `message`, `tool_use`, `tool_result`
  - dadurch landeten viele Gemini-Ereignisse im UI nur als generisches `stdout`

### Bereits vorgefunden

- Benign-`stderr`-Filter für Teile der Gemini-CLI-Ausgabe
- Instructions-Metadaten im Adapter-Invocation-Payload
- erste Unterdrückung des injizierten Initial-Prompts
- Instructions-Block im Run-Details-Panel

### Jetzt zusätzlich umgesetzt

- Unterstützung des aktuellen Gemini-Streamformats in `gemini_local`
  - `init`
  - `message`
  - `tool_use`
  - `tool_result`
- korrekte Unterdrückung des injizierten Initial-Prompts auch im aktuellen `message`-Format
- robustere Filterung des kompletten benignen `AttachConsole`-/`conpty`-Stacktraces
- sichtbare Instructions-Kurzinfo direkt im Invocation-Header, nicht nur versteckt unter `Details`
- ergänzte Tests für:
  - aktuelles Gemini-Eventformat
  - Prompt-Unterdrückung
  - Stacktrace-Filterung
  - Instructions-Metadaten

### Weiterhin offen oder separat zu behandeln

Die folgenden Punkte aus dieser Datei sind **nicht** mit dem `gemini_local`-UX-Fix erledigt und bleiben eigene Themen:

- Ben/Jules-Eskalationslogik
- Heartbeat-Strategie
- Session-Monitoring-Workflow
- Budget-/Token-Policy
- Rollen- und Disponentenlogik

Diese Punkte sind Organisations- und Workflow-Themen, keine reine Adapter-Frage.

## 📋 System-Übersicht

### Architektur

```
Paperclip (Control Plane)
├── Server (Express REST API, Port 3100)
├── UI (React + Vite)
├── Database (Drizzle ORM, PGlite/PostgreSQL)
├── Adapters
│   ├── gemini_local ← Ben verwendet diesen Adapter
│   ├── openclaw_gateway
│   ├── claude_local
│   ├── codex_local
│   ├── cursor_local
│   ├── opencode_local
│   └── pi_local
├── MCP Server (paperclip-mcp)
│   └── Tools: Issues, Agents, Goals, Approvals, Costs
└── Plugins
    └── paperclip-plugin-github-issues
```

### Ben's Konfiguration (KORRIGIERT)

- **Adapter:** `gemini_local` (NICHT openclaw)
- **Modell:** Gemini CLI lokal ausgeführt (Model-ID konfigurierbar, z.B. `gemini-2.5-pro`)
- **Funktionsweise:** Paperclip startet Gemini CLI-Prozess mit `--resume` für Session-Wiederaufnahme
- **Skills:** Auto-Injection via Symlinks nach `~/.gemini/skills/`
- **Pfad:** `C:\Users\Vinyl\Desktop\VJMapper\paperclip\packages\adapters\gemini-local\`

---

## 🔍 Analyse: Aktuelle Probleme

### 🔴 PROBLEM 1: Ben greift nicht bei hängenden Jules Sessions ein

#### Beobachtung (aus `.Jules/session-monitor-log.md`)

```
Session 13411283997285618232: Guardian - Intervall 2/3 - AWAITING_USER_FEEDBACK
Session 11217710755568478899: Palette - Intervall 1/3 - AWAITING_USER_FEEDBACK
... (6 Sessions insgesamt in AWAITING_USER_FEEDBACK)
```

#### Root Cause Analyse

**Ben's tatsächlicher Workflow (korrigiert):**

1. Ben wird von Paperclip via Heartbeat ausgeführt
2. Ben nutzt `gemini_local` Adapter → startet als lokaler Prozess
3. Ben sollte:
   - **Trigger:** Neue Jules Session erstellt → Ben beginnt Monitoring
   - **PR-Überwachung:** Sobald Session erfolgreich PR erstellt → Ben monitored PR-Checks
   - **Eskalation:** Bei hängenden Sessions → Ben sollte eingreifen

**ABER: Es fehlt die konkrete Implementierung für:**

- ✅ **Session-Erstellung-Trigger:** Woher weiß Ben dass eine neue Session erstellt wurde?
  - Paperclip erstellt Session (via Jules API oder GitHub App)
  - Ben wird per Heartbeat aktiv, aber hat keine Benachrichtigung über NEUE Sessions
  - **Lösung benötigt:** Ben muss aktiv Sessions abfragen (MCP Tool `list_issues` + Session-Status prüfen)

- ✅ **Eskalations-Logik:** Was macht Ben bei `AWAITING_USER_FEEDBACK`?
  - Intervall-Zähler existiert (1/3, 2/3, 3/3)
  - Aber: Keine definierte Aktion nach Intervall 3
  - Keine automatische "Continue"-Nachricht
  - Keine Eskalation an @MrLongNight

- ✅ **Bens Instruktionen unklar:**
  - `.agent/openclaw/AGENTS.md` war FALSCH (OpenClaw PM Agent ≠ Ben)
  - Bens tatsächliche Instruktionen müssen in Paperclip UI definiert sein (Company/Agent Config)
  - **Diese Datei ist hier NICHT einsehbar** (liegt in Paperclip UI/Datenbank)

#### Offene Fragen an @MrLongNight

1. **Wo sind Bens Instruktionen definiert?** (Paperclip UI → Agent Config?)
2. **Hat Ben den Auftrag Sessions zu erstellen?** Oder nur zu überwachen?
3. **Was soll Ben bei Intervall 3 tun?** Auto-Continue? Eskalation?

---

### 🟡 PROBLEM 2: Token-Verbrauch durch Agent-Kontexte (MUSS GEGENGECHECKT WERDEN)

#### Erste Analyse (potenziell fehlerhaft - bitte validieren!)

**Folgende Dateien enthalten Agent-Instruktionen:**

| Datei | Zweck | Geschätzte Größe | Wird geladen von |
|-------|-------|------------------|------------------|
| `.agent/AGENTS.md` | Jules-Anweisungen für VjMapper | ~3KB | Jules (immer) |
| `.agent/openclaw/AGENTS.md` | OpenClaw PM Agent (Ben?) | ~1.5KB | **Unklar** |
| `.agent/openclaw/*.md` | HEARTBEAT, IDENTITY, SOUL, TOOLS, USER | ~5KB total | **Unklar** |
| `.Jules/JULES_INTEGRATION.md` | Jules API Integration Guide | ~8KB | Jules (bei Setup) |
| `.Jules/SETUP_GUIDE.md` | Setup Guide | ~4KB | Jules (bei Setup?) |
| `.Jules/DOC-C4_AGENT_OPERATIONS.md` | Agent Operations | ~6KB | Jules? |
| `.Jules/roles/*.md` | Role-spezifische Anweisungen | ~10KB+ | Role-Agents |

**KRITISCHE FRAGE:**

- Welche Dateien lädt Ben (`gemini_local`) bei JEDEM Heartbeat?
- Welche Dateien lädt Jules bei Session-Start?
- Gibt es eine `.gemini/instructions.md` oder similar die Paperclip injiziert?

**Gegencheck erforderlich:**

- [ ] Ist `.agent/openclaw/` für Ben relevant? (Oder veraltet?)
- [ ] Nutzt Ben SOUL.md/HEARTBEAT.md/IDENTITY.md? (OpenClaw-spezifisch?)
- [ ] Lädt Jules ALLE `.Jules/*.md` Dateien? Oder nur `AGENTS.md`?
- [ ] Gibt es Paperclip-seitige Context-Limits oder Injection-Regeln?

---

### 🟡 PROBLEM 3: Jules Session Monitoring Lücke

#### Beobachtung

- Session-Monitor-Log existiert (`.Jules/session-monitor-log.md`)
- 6 Sessions sind in `AWAITING_USER_FEEDBACK`
- Intervall-Tracking exists (1/3, 2/3, 3/3)
- **ABER:** Keine automatische Eskalation dokumentiert

#### Was PASSIERT aktuell

```
Session hängt (AWAITING_USER_FEEDBACK)
  ↓
Session Monitor loggt Intervall (manuell?)
  ↓
??? (Keine definierte Eskalation)
  ↓
Session bleibt unbegrenzt hängen
```

#### Was PASSIERN sollte

```
Session hängt (AWAITING_USER_FEEDBACK)
  ↓
Ben's Heartbeat erkennt Status (via MCP `get_issue` + Session-Check)
  ↓
Intervall 1-2: Ben sendet "Continue with task" (bereits implementiert?)
  ↓
Intervall 3: Ben eskaliert an @MrLongNight + erstellt GitHub Kommentar
  ↓
Wenn > 48h: Ben pausiert Session und markiert Issue als "blocked"
```

#### Fehlende Komponenten

- [ ] **Ben's Heartbeat-Instruktionen** (Wo definiert?)
- [ ] **Eskalations-Matrix** (Was bei welchem Intervall?)
- [ ] **Automatischer Continue-Dispatch** (Send-JulesMessage via jules-api.ps1)
- [ ] **GitHub Issue Update** (Label "status: blocked" setzen)

---

### 🟡 PROBLEM 4: Jules Disponent Agent - Unvollständig?

#### Aus `.agent/AGENTS.md`

```yaml
name: jules_disponent
tools: [run_shell_command, read_file]
model: gemini-2.0-flash
```

#### Analyse

- **Tools sehr limitiert:** Nur `run_shell_command` und `read_file`
- **Kann NICHT:**
  - Dateien schreiben (`write_file` fehlt) → Keine Eskalationsberichte
  - Agents kontaktieren (`agent` Tool fehlt) → Ben nicht erreichbar
  - Code suchen (`grep_search` fehlt) → Keine Issue-Analyse
- **Modell:** `gemini-2.0-flash` (günstig, aber wenig Kontext-Tiefe)

#### Frage

- Soll der Disponent eigenständig arbeiten können?
- Oder ist er nur ein "Trigger" der PowerShell-Scripts aufruft?

---

### 🟢 PROBLEM 5: Tracker Role - Reaktiv statt Proaktiv

#### Beobachtung (aus `tracker.md`)

- Systematische Changelog-Lücken (70+ PRs auf einmal entdeckt!)
- Tracker arbeitet NACH dem Merge
- Manuelles Rekonstruieren von Git-Historie

#### Optimierungspotenzial

- **Statt:** Tracker scannt 20+ PRs → ~5000 Token/Run
- **Besser:** CI-Check blockiert PR ohne CHANGELOG-Eintrag VOR Merge
- **Einsparung:** ~80% Token-Verbrauch + keine Lücken mehr

---

### 🟢 PROBLEM 6: Session-Budget-Limits fehlen

#### Nirgends definiert (sichtbar)

- Maximale Tokens pro Jules Session
- Maximale Dauer einer Session
- Auto-Pause nach Inaktivität
- Budget-Warnschwellen

#### Risiko

- Unkontrollierter Token-Verbrauch
- Hängende Sessions verbrauchen Ressourcen

---

## 📊 Token-Verbrauch Analyse (VORLÄUFIG - Validierung erforderlich!)

### Jules Session (geschätzt)

| Kontext | Größe (Token) | Häufigkeit |
|---------|---------------|------------|
| `.agent/AGENTS.md` | ~800 | Jeder Session-Start |
| `.Jules/JULES_INTEGRATION.md` | ~2000 | Bei Setup/Referenz |
| `.Jules/SETUP_GUIDE.md` | ~1000 | Bei Setup? |
| `DOC-C4_AGENT_OPERATIONS.md` | ~1500 | Unklar |
| GitHub Issue (Prompt) | ~500-1000 | Jeder Session |
| Code-Kontext (Repo) | ~2000-5000 | Während Arbeit |
| **GESAMT (Start)** | **~4300-5300** | Pro Session |
| **GESAMT (Arbeit)** | **~2800-6300** | Pro Message |

### Ben's Heartbeat (gemini_local, geschätzt)

| Kontext | Größe (Token) | Häufigkeit |
|---------|---------------|------------|
| `.agent/openclaw/AGENTS.md` | ~400 | **Unklar** |
| `.agent/openclaw/SOUL.md` | ~300 | **Unklar** |
| `.agent/openclaw/HEARTBEAT.md` | ~200 | **Unklar** |
| Paperclip Instructions | ??? | Jeder Heartbeat |
| Issue/Session Status | ~1000 | Jeder Heartbeat |
| **GESAMT** | **~2000+???** | Pro Heartbeat |

### Offene Fragen zur Validierung

1. **Lädt Ben OpenClaw-Dateien?** (Oder sind die veraltet?)
2. **Was injiziert Paperclip als Instructions?** (Siehe `instructionsFilePath` Config)
3. **Wie oft ist Bens Heartbeat?** (Konfigurierbar in Paperclip UI)
4. **Gibt es Context-Caching?** (Gemini CLI `--resume` nutzt Session-History)

---

## 🎯 Optimierungsempfehlungen

### P0 - Sofortmaßnahmen (Kritisch)

#### 1. Ben's Eskalations-Logik implementieren

**Voraussetzung:** Ben's Instruktionen müssen definiert werden (Paperclip UI)

**Empfohlener Workflow:**

```
Heartbeat (alle X Minuten)
  ↓
MCP Tool: list_issues (Label: jules-task, State: open)
  ↓
Für jedes Issue: Session-Status prüfen (via jules-api.ps1)
  ↓
AWAITING_USER_FEEDBACK erkannt?
  ├─ Intervall 1-2: "Continue with task" senden
  └─ Intervall 3+:
      ├─ @MrLongNight erwähnen (GitHub Kommentar)
      ├─ Label "status: blocked" setzen
      └─ Session pausieren (wenn > 48h)
```

**Benötigte Tools für Ben:**

- `run_shell_command` (PowerShell: jules-api.ps1, jules-github.ps1)
- `read_file` (Session-Logs, Konfiguration)
- `write_file` (Eskalationsberichte, GitHub Kommentare)
- `grep_search` (Issues finden, Status prüfen)
- **MCP Tools:** `list_issues`, `get_issue`, `update_issue`, `comment_on_issue`

#### 2. Eskalations-Matrix definieren

| Intervall | Wartezeit | Aktion | Verantwortlich |
|-----------|-----------|--------|----------------|
| 1 | 1-6h | "Continue with task" senden | Ben (automatisch) |
| 2 | 6-24h | Erneut "Continue" + GitHub Kommentar | Ben (automatisch) |
| 3 | 24-48h | @MrLongNight erwähnen + "blocked" Label | Ben (automatisch) |
| >3 | >48h | Session pausieren + Issue als blocked markieren | Ben + Manuell |

#### 3. Session-Erstellung-Trigger klären

**Frage:** Soll Ben Sessions erstellen ODER nur überwachen?

**Option A - Ben erstellt Sessions:**

```
GitHub Issue (Label: jules-task) erstellt
  ↓
Ben's Heartbeat erkennt neues Issue
  ↓
Ben erstellt Session (via jules-api.ps1 oder Jules GitHub App)
  ↓
Ben beginnt Monitoring
```

**Option B - Sessions werden extern erstellt:**

```
GitHub Workflow / Manuelles Trigger erstellt Session
  ↓
Ben's Heartbeat scannt offene Issues + Sessions
  ↓
Ben erkennt neue Session → beginnt Monitoring
```

**Empfehlung:** Option B (weniger Token-Verbrauch, Ben muss nicht Issues ständig pollen)

---

### P1 - Mittelfristige Optimierungen

#### 4. Agent-Kontexte konsolidieren (NACH Validierung!)

**Voraussetzung:** Gegencheck welche Dateien wirklich geladen werden

**Wenn OpenClaw-Dateien für Ben irrelevant:**

- `.agent/openclaw/` löschen oder archivieren
- **Einsparung:** ~2KB pro Heartbeat (wenn geladen)

**Wenn Jules redundante Docs lädt:**

- `JULES_INTEGRATION.md` + `SETUP_GUIDE.md` → eine Master-Datei
- **Einsparung:** ~3000 Token pro Session-Start

#### 5. Heartbeat-Intervall anpassen

**User-Statement:** "Sobald es wie gewünscht funktioniert werde ich vermutlich den Heartbeat Intervall erhöhen"

**Empfehlung:**

```
Startphase (Jetzt):     Alle 5-10 Minuten (häufiges Monitoring)
Nach Stabilisierung:    Alle 30-60 Minuten (reduzierter Verbrauch)
Nachts/Weekends:        Alle 2-4 Stunden (minimaler Verbrauch)
```

**Implementierung:** Paperclip UI → Agent Config → Heartbeat Schedule

#### 6. Session-Budget-Limits einführen

**In Paperclip UI definieren:**

```yaml
agent_budgets:
  jules_sessions:
    max_tokens_per_session: 500000
    max_duration_hours: 48
    auto_pause_after_idle_hours: 12
    alert_threshold_percent: 80

  ben_heartbeat:
    max_tokens_per_run: 50000
    max_issues_per_scan: 20
    cache_session_status_minutes: 15
```

---

### P2 - Langfristige Verbesserungen

#### 7. PR-Template Enforcement in CI

**Statt Tracker der nachbessert:**

- Pre-commit Hook prüft CHANGELOG-Eintrag
- GitHub Action blockiert Merge ohne CHANGELOG
- **Einsparung:** ~5000 Token/Tracker-Run + keine Lücken mehr

#### 8. Token-Usage-Tracking implementieren

**Paperclip Feature:** `get_cost_summary` (MCP Tool) existiert bereits!

**Empfehlung:**

- Wöchentlichen Report erstellen
- Pro Agent/Session Kosten tracken
- Optimierungspotenziale identifizieren

#### 9. Agent-Rollen klarer trennen

| Agent | Verantwortung | Tools | Heartbeat |
|-------|--------------|-------|-----------|
| Ben (PM) | Session-Monitoring, Eskalationen | MCP + PowerShell | Alle 30min |
| Jules | Code-Implementierung | Gemini CLI | Session-basiert |
| Tracker | QA-Checks (NICHT Changelog) | git, grep | Wöchentlich |
| Guardian | Test-Abdeckung | cargo test | Bei PRs |
| Sentinel | Security-Audits | cargo audit | Wöchentlich |

---

## ❓ Offene Fragen an @MrLongNight

### Kritisch (P0)

1. **Wo sind Bens Instruktionen definiert?** (Paperclip UI? Datei? Beides?)
2. **Hat Ben den Auftrag Jules Sessions zu erstellen?** Oder nur Monitoring?
3. **Was soll Ben bei Intervall 3 tun?** (Auto-Continue? Eskalation an mich?)
4. **Sind `.agent/openclaw/*` Dateien noch relevant für Ben?** (Oder veraltet?)

### Wichtig (P1)

1. **Wie oft läuft Bens Heartbeat aktuell?** (Konfiguration in Paperclip?)
2. **Gibt es eine `instructionsFilePath` für Ben?** (Welche Datei wird injiziert?)
3. **Soll der Jules Disponent mehr Tools bekommen?** (write_file, agent, grep_search)
4. **Gibt es bereits Budget-Limits in Paperclip?** (Oder muss das definiert werden?)

### Validierung (Token-Analyse)

1. **Welche Dateien lädt Ben bei JEDEM Heartbeat?**
2. **Welche Dateien lädt Jules bei Session-Start?**
3. **Nutzt Paperclip Context-Caching?** (Oder wird alles neu geladen?)
4. **Gibt es redundante Docs die konsolidiert werden können?**

---

## 📝 Nächste Schritte

### Sofort (nach Validierung)

1. @MrLongNight beantwortet offene Fragen (insb. Wo sind Bens Instruktionen?)
2. Gegencheck der Token-Annahmen (Welche Dateien werden wirklich geladen?)
3. Eskalations-Matrix definieren und freigeben

### Nach Freigabe

1. Ben's Instruktionen aktualisieren (Eskalations-Logik)
2. PowerShell-Scripts für Auto-Continue erweitern
3. Heartbeat-Intervall dokumentieren und optimieren
4. Session-Budget-Limits definieren

### Langfristig

1. Agent-Kontexte konsolidieren (nach Validierung der Redundanzen)
2. CI-Checks für Changelog-Pflicht implementieren
3. Token-Usage-Reports einrichten

---

## 📚 Referenzen

### Paperclip Architektur

- `C:\Users\Vinyl\Desktop\VJMapper\paperclip\doc\PRODUCT.md`
- `C:\Users\Vinyl\Desktop\VJMapper\paperclip\doc\SPEC-implementation.md`
- `C:\Users\Vinyl\Desktop\VJMapper\paperclip\packages\adapters\gemini-local\src\index.ts`

### Jules Integration

- `.Jules/JULES_INTEGRATION.md`
- `.Jules/session-monitor-log.md`
- `scripts/jules/jules-api.ps1`
- `scripts/jules/jules-github.ps1`

### Agent Konfigurationen

- `.agent/AGENTS.md`
- `.agent/openclaw/AGENTS.md` (Status unklar!)
- `.Jules/roles/*.md`

---

**Letztes Update:** 2026-04-11
**Version:** 1.0 (Entwurf - Validierung erforderlich)
**Nächste Aktion:** User-Feedback zu offenen Fragen + Gegencheck der Token-Annahmen
