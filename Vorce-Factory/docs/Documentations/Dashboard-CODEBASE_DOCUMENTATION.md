# Vorce-Factory Dashboard - Codebase Documentation

**Last Updated**: 2026-06-07  
**Analyzed By**: Hermes Agent  

---

## Project Structure

```
Vorce-Factory/dashboard/
├── src/
│   ├── pages/
│   │   ├── DashboardPage.tsx         (869 lines, 39.7KB) - MAIN DASHBOARD
│   │   ├── SettingsPage.tsx          (808 lines, 39.4KB) - SETTINGS UI
│   │   ├── WorkstreamsPage.tsx       (100+ lines)       - WORKSTREAMS
│   │   ├── ManagerReportingPage.tsx  (100+ lines)       - REPORTING
│   │   ├── DeliberationPanel.tsx     (198 lines, 9KB)   - CEO CHAT
│   │   ├── MemoryPanel.tsx           (100+ lines)       - MEMORY STORE
│   │   └── App.tsx                   (214 lines, 8.8KB) - MAIN APP + NAV
│   ├── main.tsx                      (10 lines)         - ENTRY POINT
│   ├── hooks.ts                      (100+ lines)       - CUSTOM HOOKS
│   ├── types.ts                      (100+ lines)       - TYPESCRIPT TYPES
│   └── index.css                     (100+ lines)       - STYLES
├── index.html
├── vite.config.ts
└── package.json
```

---

## File-by-File Analysis

### 1. main.tsx (10 lines)

**Purpose**: React entry point with StrictMode.

**Imports**:

- React, ReactDOM
- App component
- index.css

**Features**:

- `createRoot` with StrictMode
- Single entry point

---

### 2. App.tsx (214 lines)

**Purpose**: Main application with navigation and data fetching.

**Tabs**:

- `dashboard` → DashboardPage
- `workstreams` → WorkstreamsPage
- `reporting` → ManagerReportingPage
- `settings` → SettingsPage

**Data Hooks**:

- config (AutopilotConfig)
- registry (QuotaRegistry)
- sessions (ActiveSessions)
- issues (GitHubIssue[])
- pullRequests (PullRequest[])
- projectItems (any[])
- julesSessions (any[])
- memoryStore (MemoryStore)
- history (any[])
- auditResult (AuditResult)
- liveLog (string)

**Auto-Refresh**: Every 30 seconds

**Features**:

- Navigation sidebar
- Header with refresh button
- Dynamic page rendering
- Loading states

---

### 3. DashboardPage.tsx (869 lines)

**Purpose**: Central dashboard with system overview.

**Key Components**:

- Status Banner (System status, session ID)
- Audit Alert Box (Last audit issues)
- Audit Alerts (Pending alerts table)
- Run Cards für alle fünf MAIN-RUNs
- Live Log Panel (Real-time logs)
- Working Sessions Panel (Jules sessions)
- Review Queue (PR reviews)
- KPI Cards (Costs, Sessions, PRs, Completed)
- Provider Chart (Recharts visualization)
- Optimizer Queue (Optimization proposals)
- Deliberation Panel (CEO chat)

**Helper Functions**:

- `formatCost()` - Format USD
- `timeAgo()` - Relative time
- `normalizeAuditText()` - Label normalization
- `shortText()` - Truncate text
- `auditOwnerLabel()` - Determine owner
- `auditStageLabel()` - Determine stage
- `updateAuditAlert()` - API call
- `parseAuditResult()` - JSON parsing
- `simplifyLiveLogLine()` - Parse log line
- `getLiveLogItems()` - Get log array
- `formatNextRun()` - Format next run time

**Status**: ✅ Repariert, stabil >297 Sekunden

---

### 4. DeliberationPanel.tsx (198 lines)

**Purpose**: Dual-CEO deliberation view.

**Features**:

- Expandable chat history
- Consensus indicators
- Round-based display
- Provider identification

**Functions**:

- `timeAgo()` - Relative timestamps

**Status**: ✅ Komplett

---

### 5. SettingsPage.tsx (808 lines)

**Purpose**: Full system configuration via UI.

**Sections**:

1. **Autopilot Core**: Repository, Wake Intervals, Gemini Path
2. **Jules Orchestration**: Sessions, Retries, Auto-Approve
3. **Working Sessions**: Enabled, Max Concurrent, Preferred Agents
4. **GitHub Issue Filter**: Include/Exclude Labels
5. **CEO + QA Manager Deliberation**: Enabled, Chain, Max Rounds
6. **Provider Routing**: Task types to providers
7. **LLM Models**: Per-provider model config
8. **Prompt Configuration**: 16 predefined prompts
9. **Memory Store**: CRUD operations

**Functions**:

- `handleConfigChange()` - Top-level config
- `handleNestedConfigChange()` - Nested config
- `handleProviderChange()` - Provider settings
- `handleRoutingChange()` - Routing rules
- `handleDualCeoArrayChange()` - CEO arrays
- `handleWorkingSessionsArrayChange()` - Working sessions
- `handlePromptChange()` - Prompt settings
- `handleProviderModelChange()` - Model settings
- `handleSave()` - Save all config

**Status**: ✅ Komplett

---

### 6. WorkstreamsPage.tsx

**Purpose**: Workstream management (To be analyzed).

**Features** (Expected):

- Issue lists
- Workstream status
- Filter options

---

### 7. ManagerReportingPage.tsx

**Purpose**: Manager reporting dashboard (To be analyzed).

**Features** (Expected):

- Performance metrics
- Summary charts
- Export options

---

### 8. MemoryPanel.tsx

**Purpose**: Memory store UI (To be analyzed).

**Features** (Expected):

- Memory CRUD
- Search
- Categories

---

## TypeScript Types

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
      models: { [modelKey]: { name: string, estimated_cost_per_call_usd: number } },
      routing_rules: { [taskType]: string[] }
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
  jules: { max_daily_sessions: number, max_concurrent_sessions: number, auto_approve_plans: boolean, auto_retry_feedback_max: number },
  gemini_worktree_path: string,
  issue_filters: { include_labels: string[], exclude_labels: string[], autopilot_label: string },
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
  prompts: { [promptKey]: string }
}
```

---

## JSX-Syntax Rules

### ✅ Valid Patterns

```tsx
// Map-Closing
{items && items.map((item, idx) => (
  <div key={item.id}>{item.name}</div>
))}

// Conditional Render
{condition && (
  <div>Content</div>
)}

// Comments before closing
{/* Comment */}
)}


// RunCard outside conditional
{items && items.length > 0 && (
  <AuditBlock />
)}
<RunCard />
```

### ❌ Invalid Patterns

```tsx
// Invalid map closing
{items && items.map(item => <div />) })}  // ❌

// Inline comment after )
<div />)} {/* Comment */}  // ❌

// Component inside conditional
{condition && (
  <div>
    <Component />)}  // ❌
  </div>
)}
```

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/alerts` | POST | Update audit alert |
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
| `/jules-sessions.json` | GET | Jules sessions |
| `/memories.json` | GET | Memory store |
| `/data.json` | GET | History data |
| `/audit-result.json` | GET | Audit result |
| `/live-log.json` | GET | Live log |

---

## Known Issues & Fixes

### Issue 1: JSX Parse-Fehler (REPARIERT)

- **Problem**: Map-Closing `) })}` falsch verschachtelt
- **Lösung**: `{` + `)` + `})` + `)` korrekt platziert
- **Status**: ✅ Repariert

### Issue 2: RunCard in Audit Block (REPARIERT)

- **Problem**: RunCard innerhalb von `&& (` Block
- **Lösung**: RunCard außerhalb `&& (` platziert
- **Status**: ✅ Repariert

### Issue 3: Inline Comment nach `)` (REPARIERT)

- **Problem**: Kommentar direkt nach `)` (nicht erlaubt)
- **Lösung**: `{/* Comment */}` + newline + `)`
- **Status**: ✅ Repariert

### Issue 4: Repo-Defekt (WORKAROUND)

- **Problem**: Git-Repo enthält corrupte JSX
- **Lösung**: `write_file()` statt `git checkout` verwenden
- **Status**: ✅ Workaround implementiert

### Issue 5: Oxc/Vite Caching (RESOLVED)

- **Problem**: File changes nicht sichtbar durch Caching
- **Lösung**: Port erhöhen + Cache löschen
- **Status**: ✅ Verstanden

---

## Optimization Opportunities

### Performance

1. **Memoization**: chartData, liveLogItems, julesSession counts
2. **React.Fragment**: Überflüssige divs vermeiden
3. **Lazy Loading**: Components mit `lazy()` laden

### Type Safety

1. **Replace `any`**: Spezifische Types verwenden
2. **Interfaces**: Für komplexe Objekte definieren

### Reliability

1. **Error Boundaries**: Fallback-UI für React-Fehler
2. **Suspense**: Loading States zentralisieren

### UX

1. **Toast Notifications**: Erfolgs/Fehler-Meldungen
2. **Keyboard Navigation**: Shortcut support
3. **Progress Indicators**: Loading für längere操作

---

## Dev Server

### Start

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

- Aktuell: Port 5234 (stable >616s)
- Bei Restart: Port erhöhen (5235, 5236, etc.)
- Cache immer nach Änderungen löschen
- **CRITICAL**: Oxc/Vite Cache `rm -rf node_modules/.vite && rm -rf .vite` vor jeder Reparatur!
- **CRITICAL**: Port-Inkrement erforderlich nach jedem Restart (5234 → 5235)
- **CRITICAL**: Python `execute_code` statt PowerShell für Datei-Edit (keine Escape-Sequenzen)
- **Stabilität**: >616 Sekunden ohne Parse-Fehler (Dev Server proc_78a7f28c91c0)

---

## Debugging Protocol (Skill: vorce-autopilot-dashboard-debug)

## Build & Deployment

### Development

```bash
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

### Reparatur-Command

```bash
# Datei komplett neu schreiben (nicht git checkout!)
# Python execute_code verwenden für echte \n Newlines
```

### Cache-Lösch-Pattern

```bash
rm -rf node_modules/.vite && rm -rf .vite
```

---

**Built with Vite & React**
**© 2026 Vorce Autopilot**
