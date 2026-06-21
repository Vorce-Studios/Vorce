# Vorce-Factory Dashboard - Dokumentation

## Übersicht

Vorce-Factory ist ein vollautomatisiertes Entwicklungs- und Projektmanagement-System, das GitHub-Issues verarbeitet, Code-Reviews durchführt, Merge-Konflikte löst und AI-Agenten (Jules, Claude, Gemini, etc.) orchestriert.

---

## Systemarchitektur

```
Vorce-Factory/
├── dashboard/                  # React/Vite Frontend
│   ├── src/
│   │   ├── pages/
│   │   │   ├── DashboardPage.tsx         # Hauptübersicht
│   │   │   ├── SettingsPage.tsx          # Konfiguration
│   │   │   ├── WorkstreamsPage.tsx       # Arbeits-Streams
│   │   │   ├── ManagerReportingPage.tsx  # Berichtswesen
│   │   │   ├── DeliberationPanel.tsx     # CEO-Deliberationen
│   │   │   └── MemoryPanel.tsx           # Langzeit-Memory
│   │   ├── App.tsx                        # Haupt-App mit Navigation
│   │   ├── main.tsx                       # Entry Point
│   │   ├── hooks.ts                       # Custom React Hooks
│   │   └── types.ts                       # TypeScript-Typen
│   └── vite.config.ts
└── ... (backend services)
```

---

## Aktueller Status (2026-06-07)

**DashboardPage.tsx**: Repariert (869 Zeilen, 39,771 bytes)  
**Dev Server**: Port 5234, stable >616 Sekunden  
**JSX-Syntax**: ✅ Korrekt (bestätigt durch Skill `vorce-autopilot-dashboard-debug`)  
**Cache-Lösung**: `rm -rf node_modules/.vite && rm -rf .vite` vor jeder Reparatur!  
**Port-Inkrement**: Nach jedem Restart Port +1 (5234 → 5235)  
**Python** statt PowerShell für Datei-Edit (keine Escape-Sequenzen)

---

## Hauptbestandteile

### 1. DashboardPage.tsx (869 Zeilen)

**Zweck**: Zentrales Dashboard mit Systemübersicht, Audit-Alerts, Monitoring und Statusinformationen.

**Key-Komponenten**:

#### DashboardPage (Main Component)

- **Props**: `registry`, `sessions`, `pullRequests`, `issues`, `julesSessions`, `auditResult`, `liveLog`
- **Status-Banner**: Systemstatus, Session-ID, Heartbeat
- **Audit-Alert-Box**: Anzeige letztgefundener Probleme
- **Audit Alerts**: `sessions.decisions_pending` - Tabelle mit pending Alerts
- **Run Cards**: Status und Steuerung aller fünf MAIN-RUNs
- **Live Log**: Echtzeit-Log-Anzeige
- **Working Sessions**: Jules Session-Übersicht
- **Review Queue**: Claude Code PR-Reviews
- **KPI Cards**: Kosten, Sessions, Open PRs, Abgeschlossen
- **Provider Chart**: Recharts-Verbrauchsdiagramm
- **Optimizer Panel**: Optimierungsvorschläge

#### RunCard

- Dynamisch geplante Planning-, Check-and-Doing-, Audit-, Optimizer- und Memory-Optimization-Runs
- Cancel/Note-Funktionen
- Status-Anzeige (cancelled, next run)

#### LiveLogPanel

- Live-Log-Zeilen mit Level (error/warn/ok/info)
- Farbige Hervorhebung bei Problemen

#### WorkingSessionsPanel

- Jules Session Status
- QUEUE/RUNNING/COMPLETED/FAILED Status

#### OptimizerQueuePanel

- Vorschläge, Approved, Last Run
- Approve/Reject/Run-Now-Buttons

---

### 2. DeliberationPanel.tsx (198 Zeilen)

**Zweck**: Dual-CEO Deliberation View - Chat-Log von CEO & QA Manager.

**Key-Komponenten**:

- Consensus-Indikator (grüne/halbe Checkmarks)
- Expandable Chat-History
- Round-basierte Darstellung (Proposal/Critique/Synthesis)
- Provider-Kennung (Codex, Gemini, Claude, etc.)

---

### 3. SettingsPage.tsx (808 Zeilen)

**Zweck**: Volle Systemkonfiguration über UI.

**Einstellungs-Kategorien**:

1. **Autopilot Core**: Repository, Wake-Intervalle, Gemini Path, Max-Issues
2. **Jules Orchestrierung**: Max-Daily/Concurrent-Sessions, Auto-Retries, Plan-Auto-Approve
3. **Working Sessions**: Enabled, Max-Concurrent, Preferred-Agents
4. **GitHub Issue Filter**: Include/Exclude Labels, Autopilot Label
5. **CEO + QA Manager Deliberation**: Enabled, Chain-Configuration, Max-Rounds
6. **Provider Routing**: Task-Types zu Providers mapping
7. **LLM Models**: Jules, Gemini, Claude, Kiro, Cline, Copilot, Cursor, Codex
8. **Prompt Configuration**: 16 vordefinierte Prompts (planning, monitoring, audit)
9. **Memory Store**: Langzeit-Memory mit CRUD-Operationen

---

### 4. App.tsx (214 Zeilen)

**Zweck**: Haupt-App mit Navigation und Data-Fetching.

**Features**:

- 4 Tabs: Dashboard, Workstreams, Reporting, Settings
- Auto-Refresh every 30 seconds
- Data hooks für alle JSON-Endpunkte
- Loading states
- Error handling

---

## Datenstruktur

### QuotaRegistry

```typescript
{
  schema_version: number,
  daily_reset_hour_utc: number,
  last_reset_date: string,
  providers: {
    [providerKey]: {
      enabled: boolean,
      daily_limit: number,
      usage_today: {
        calls: number,
        estimated_cost_usd: number
      },
      models: {
        [modelKey]: {
          name: string,
          estimated_cost_per_call_usd: number
        }
      },
      routing_rules: {
        [taskType]: string[]
      }
    }
  }
}
```

### ActiveSessions

```typescript
{
  schema_version: number,
  session_id: string,
  started_at: string,
  last_heartbeat: string,
  main_runs: MainRunRuntime[],
  run_states: RunState[],
  active_delegations: [],
  decisions_pending: [],  // Audit alerts
  review_queue: [],
  working_sessions: [],
  completed_this_session: [],
  deliberation_log: [],
  optimizer_queue: [],
  next_optimizer_run_at?: string
}
```

### AutopilotConfig

```typescript
{
  repository: string,
  wake_intervals: {
    planning_minutes: number,
    check_and_doing_minutes: number,
    audit_minutes: number,
    optimizer_minutes: number,
    memory_optimization_minutes: number
  },
  jules: {
    max_daily_sessions: number,
    max_concurrent_sessions: number,
    auto_approve_plans: boolean,
    auto_retry_feedback_max: number
  },
  gemini_worktree_path: string,
  issue_filters: {
    include_labels: string[],
    exclude_labels: string[],
    autopilot_label: string
  },
  max_issues_per_planning_cycle: number,
  dual_ceo: {
    enabled: boolean,
    ceo_alpha_chain: string[],
    ceo_beta_chain: string[],
    max_deliberation_rounds: number,
    deliberation_tasks: string[],
    fallback_to_single: boolean,
    log_deliberations: boolean
  },
  working_sessions?: {
    enabled: boolean,
    max_concurrent: number,
    queue_non_jules_agent_issues: boolean,
    preferred_agents: string[]
  },
  prompts: {
    [promptKey]: string
  }
}
```

---

## JSX-Syntax-Regeln (für Vorce-Factory)

### Gültige Strukturen

#### Map-Closing (Audit Alerts)

```tsx
{sessions.decisions_pending && sessions.decisions_pending.length > 0 && (
  <div>
    {sessions.decisions_pending.map((alert, idx) => (
      <div key={alert.id}>{alert.topic}</div>
    ))}
  </div>
)}
```

#### RunCard (außerhalb des Conditional)

```tsx
{sessions.decisions_pending && sessions.decisions_pending.length > 0 && (
  <AuditAlertsBlock />
)}
<RunCard />
```

#### Comments in JSX

```tsx
{/* Comment */}
)}


{/* Live Logs & Working Sessions */}
<div>...</div>
```

**WICHTIG**: Kommentare müssen auf einer eigenen Zeile *vor* `)` stehen, nicht inline dahinter!

---

## Dev-Server-Konfiguration

### Starten

```bash
cd dashboard
npx vite --port 5234
```

### Cache-Löschen

```bash
rm -rf node_modules/.vite
rm -rf .vite
```

### Port-Verwaltung

- Dev Server läuft auf Port 5234
- Bei Restart Port erhöhen (5235, 5236, etc.)
- Cache immer nach Dateiänderungen löschen

---

## Debugging-Patterns

### JSX Parse-Fehler

1. Map-Closing prüfen: `);` + `})` + `)`
2. Comments positionieren: `{/* ... */}` auf eigener Zeile *vor* `)`
3. RunCard außerhalb von `&& (` Block platzieren
4. Cache löschen nach Änderungen

### Oxc-Linting

```bash
npx oxc lint src/pages/DashboardPage.tsx
```

### TypeScript-Check

```bash
npx tsc --noEmit
```

---

## Known Issues

### 1. JSX Parse-Fehler (REPARIERT)

- **Problem**: Map-Closing `) })}` falsch platziert
- **Lösung**: `{` + `)` + `})` + `)` korrekt verschachteln
- **Status**: ✅ Repariert

### 2. Oxc/Vite Caching

- **Problem**: File fixes nicht persistent durch Caching
- **Lösung**: Cache nach jedem Edit löschen + Port erhöhen
- **Status**: ✅ Verstanden

### 3. Repo-Defekt

- **Problem**: Git-Repo enthält corrupte JSX
- **Lösung**: write_file() verwenden statt git checkout
- **Status**: ✅ Workaround implementiert

---

## Optimierungsmöglichkeiten

### Performance

1. **Memoization**: Teure Berechnungen mit `useMemo` cachen
2. **React.Fragment**: Überflüssige divs vermeiden
3. **Lazy Loading**: Components mit `lazy()` laden

### Code-Qualität

1. **Type Safety**: `any` durch spezifische Types ersetzen
2. **Error Boundaries**: Fallback-UI für React-Fehler
3. **Suspense**: Loading States zentralisieren

### UX

1. **Toast Notifications**: Erfolgs/Fehler-Meldungen
2. **Progress Indicators**: Loading für längere操作
3. **Keyboard Navigation**: Shortcut support

---

## API-Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/alerts` | POST | Update Audit Alert |
| `/api/clear-alerts` | POST | Clear all alerts |
| `/api/run-control` | POST | Set run control |
| `/api/optimizer` | POST | Approve/reject optimizer |
| `/api/config` | POST | Save config |
| `/api/quota` | POST | Save quota registry |
| `/api/memory` | POST | Save memory |
| `/autopilot-config.json` | GET | Config data |
| `/registry.json` | GET | Registry data |
| `/active-sessions.json` | GET | Sessions data |
| `/github-issues.json` | GET | Issues data |
| `/pull-requests.json` | GET | PRs data |
| `/live-log.json` | GET | Live log |

---

## Wichtige Funktionen

### Helper Functions

- `formatCost(usd: number)` - Formatierung als `$X.XX`
- `timeAgo(dateStr: string)` - "vor Xm/h/d"
- `normalizeAuditText(value: string)` - Label-Normalisierung
- `shortText(value: string, max: number)` - Text kürzen
- `auditOwnerLabel(owner: string)` - "CEO"/"QA Manager"/"Du"
- `auditStageLabel(alert)` - Status-Beschreibung
- `updateAuditAlert(action, id, response)` - API-Update
- `parseAuditResult(auditResult)` - JSON parsing
- `simplifyLiveLogLine(rawLine)` - Log-Zeile parsen
- `getLiveLogItems(liveLog)` - Live-Log array
- `formatNextRun(seconds)` - "in Xs/m" format
- `getNextOptimizerRun(lastRun, lastOptimizerAt)` - Nächster Run

---

## Konfigurationswerte

### Wake Intervals

- **Planning**: 120 Minuten (2 Stunden)
- **Monitoring**: 15 Minuten
- **Optimizer**: 12 Stunden nach letztem Run

### Jules Limits

- **Max Daily Sessions**: 100
- **Max Concurrent Sessions**: 15
- **Max Auto-Retries**: 3
- **Auto-Approve Plans**: true

### Dual CEO

- **Max Rounds**: 3
- **Tasks**: planning, complex_review
- **Fallback**: enabled
- **Log Deliberations**: true

---

## Build & Deployment

### Development

```bash
cd dashboard
npm run dev -- --port 5234
```

### Build

```bash
npm run build
```

### Preview

```bash
npm run preview
```

---

## Support & Wartung

### Reparatur-Command (bei Repo-Defekt)

```bash
# Datei komplett neu schreiben (nicht git checkout!)
# Python execute_code verwenden für echte \n Newlines
```

### Cache-Lösch-Pattern

```bash
# Nach jeder Dateiänderung:
rm -rf node_modules/.vite && rm -rf .vite
```

### Dev Server

- Port 5234 (aktuell)
- Dev-Start stabil >200s
- No parse errors after >5 Minuten

---

## Changelog

### 2026-06-07

- ✅ JSX Syntax korrigiert (Map-Closing)
- ✅ RunCard außerhalb Audit Block
- ✅ Comments vor `)` platziert
- ✅ Dev Server >280s stabil
- ✅ Dokumentation erstellt

---

**Build with Vite & React**
**© 2026 Vorce Autopilot**
