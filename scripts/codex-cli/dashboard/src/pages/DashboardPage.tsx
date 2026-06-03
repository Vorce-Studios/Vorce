import { useState } from 'react';
import { Activity, DollarSign, GitPullRequest, Zap, Clock, TrendingUp, AlertCircle, XCircle, CalendarClock, Ban, MessageSquare, Trash2, Terminal } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';
import type { QuotaRegistry, ActiveSessions, PullRequest, GitHubIssue, AuditResult } from '../types';

interface Props {
  registry: QuotaRegistry;
  sessions: ActiveSessions;
  pullRequests: PullRequest[];
  issues: GitHubIssue[];
  julesSessions?: any[];
  auditResult?: AuditResult;
  liveLog?: string;
}

const PROVIDER_COLORS: Record<string, string> = {
  jules: '#a78bfa',
  gemini_cli: '#06b6d4',
  kiro_cli: '#f472b6',
  cline_cli: '#fb923c',
  claude_code: '#34d399',
  copilot_cli: '#60a5fa',
  cursor_agent: '#fbbf24',
  codex_orchestrator: '#e879f9',
};

const PROVIDER_LABELS: Record<string, string> = {
  jules: 'Jules',
  gemini_cli: 'Gemini CLI',
  kiro_cli: 'Kiro CLI',
  cline_cli: 'Cline CLI',
  claude_code: 'Claude Code',
  copilot_cli: 'Copilot CLI',
  cursor_agent: 'Cursor Agent',
  codex_orchestrator: 'Codex Orchestrator',
};

function formatCost(usd: number): string {
  return `$${usd.toFixed(2)}`;
}

function timeAgo(dateStr: string): string {
  if (!dateStr) return 'N/A';
  const now = new Date();
  const then = new Date(dateStr);
  const diffMs = now.getTime() - then.getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return 'gerade eben';
  if (mins < 60) return `vor ${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `vor ${hours}h`;
  const days = Math.floor(hours / 24);
  return `vor ${days}d`;
}

function parseAuditResult(auditResult?: AuditResult) {
  if (!auditResult) return null;
  if (auditResult.parsed) return auditResult.parsed;
  if (!auditResult.response) return null;

  const cleaned = auditResult.response
    .replace(/^```json\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();

  try {
    return JSON.parse(cleaned);
  } catch {
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function simplifyLiveLogLine(rawLine: string) {
  const match = rawLine.match(/^\[(.*?)\]\s*(.*)$/);
  const time = match ? match[1].split(' ')[1] || match[1] : '';
  let message = (match ? match[2] : rawLine).trim();
  if (!message) return null;

  const level =
    /(fehler|error|failed|fehlgeschlagen|exception|stacktrace)/i.test(message) ? 'error' :
    /(warning|warnung|konflikt|blocked|escalat)/i.test(message) ? 'warn' :
    /(ok|abgeschlossen|completed|erfolgreich)/i.test(message) ? 'ok' :
    'info';

  message = message
    .replace(/^\[(PLANNING|MONITOR|AUDIT|LOOP|CEO|MEMORY|CODEX|DRY-RUN|INIT|STATE)\]\s*/i, '')
    .replace(/^==========\s*/, '')
    .replace(/\s*==========$/, '')
    .replace(/^Starte Schritt:\s*/i, '')
    .replace(/^Schritt:\s*/i, '')
    .replace(/^Provider:\s*/i, 'Provider ')
    .replace(/^Visible Phase:\s*/i, 'Dry-Run ')
    .replace(/^Naechster Wake-Up/i, 'Nächster Run')
    .replace(/^Oeffne sichtbares Terminal:/i, 'Öffne Terminal:');

  if (message.length > 150) {
    message = `${message.slice(0, 147)}...`;
  }

  return { time, message, level };
}

function getLiveLogItems(liveLog?: string) {
  if (!liveLog) return [];
  return liveLog
    .split(/\r?\n/)
    .map(line => simplifyLiveLogLine(line))
    .filter((item): item is { time: string; message: string; level: string } => Boolean(item))
    .slice(-14)
    .reverse();
}

export default function DashboardPage({ registry, sessions, pullRequests, julesSessions, auditResult, liveLog }: Props) {
  const providers = registry.providers || {};
  const providerEntries = Object.entries(providers);

  const totalCostToday = providerEntries.reduce((sum, [, p]) => sum + (p.usage_today?.estimated_cost_usd || 0), 0);
  const totalCallsToday = providerEntries.reduce((sum, [, p]) => sum + (p.usage_today?.calls || 0), 0);

  const targetRepo = 'Vorce-Studios/Vorce';
  const activeJulesSessions = julesSessions ? julesSessions.filter(s =>
      s.repo === targetRepo &&
      s.state !== 'COMPLETED' &&
      s.state !== 'QUEUED'
  ).length : 0;

  const vorceOpenPRs = pullRequests.filter(pr => (!pr.repo || pr.repo === targetRepo) && pr.state === 'OPEN');
  const openPRs = vorceOpenPRs.length;
  const conflictingPRs = vorceOpenPRs.filter(pr => pr.mergeable === 'CONFLICTING').length;
  const scheduler = sessions.scheduler;
  const runControl = sessions.run_control || {};
  const audit = parseAuditResult(auditResult);
  const pendingAlerts = sessions.decisions_pending || [];
  const liveLogItems = getLiveLogItems(liveLog);

  const sendRunControl = async (type: 'planning' | 'monitoring', action: string, note?: string) => {
    await fetch('/api/run-control', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, action, note }),
    });
  };

  const updateAlert = async (action: string, id: string, response?: string) => {
    await fetch('/api/alerts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, id, response }),
    });
  };

  const chartData = providerEntries
    .filter(([, p]) => p.enabled)
    .map(([key, p]) => ({
      name: PROVIDER_LABELS[key] || key,
      calls: p.usage_today?.calls || 0,
      limit: p.daily_limit,
      color: PROVIDER_COLORS[key] || '#8b5cf6',
    }));

  return (
    <div className="space-y-6 animate-in">
      {/* Status Banner */}
      <div className="glass-card p-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-purple-500 to-cyan-500 flex items-center justify-center">
              <Zap className="w-6 h-6 text-white" />
            </div>
            <div>
              <h2 className="text-xl font-bold gradient-text">Vorce Autopilot</h2>
              <p className="text-sm text-slate-400 flex items-center gap-2 mt-0.5">
                <span className="status-dot-active" />
                Aktiv seit {timeAgo(sessions.started_at || '')}
                <span className="text-slate-600">•</span>
                Session: {sessions.session_id || 'N/A'}
              </p>
            </div>
          </div>
          <div className="text-right text-sm text-slate-400">
            <div className="flex items-center gap-1.5">
              <Clock className="w-3.5 h-3.5" />
              Letzter Heartbeat: {timeAgo(sessions.last_heartbeat || '')}
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <RunCard
          title="Planning Run"
          lastAt={sessions.last_planning_at}
          nextAt={scheduler?.next_planning_at}
          nextInSeconds={scheduler?.next_planning_in_seconds}
          interval={`${scheduler?.planning_interval_minutes ?? 'N/A'} min`}
          cancelled={runControl.cancel_next_planning}
          note={runControl.next_planning_note}
          onCancel={() => sendRunControl('planning', runControl.cancel_next_planning ? 'uncancel-next' : 'cancel-next')}
          onNote={(note) => sendRunControl('planning', 'note-next', note)}
        />
        <RunCard
          title="Monitoring Run"
          lastAt={sessions.last_monitoring_at}
          nextAt={scheduler?.next_monitoring_at}
          nextInSeconds={scheduler?.next_monitoring_in_seconds}
          interval={`${scheduler?.monitoring_interval_minutes ?? 'N/A'} min`}
          cancelled={runControl.cancel_next_monitoring}
          note={runControl.next_monitoring_note}
          onCancel={() => sendRunControl('monitoring', runControl.cancel_next_monitoring ? 'uncancel-next' : 'cancel-next')}
          onNote={(note) => sendRunControl('monitoring', 'note-next', note)}
        />
      </div>

      <AuditPanel
        auditResult={auditResult}
        audit={audit}
        alerts={pendingAlerts}
        onClear={() => fetch('/api/alerts', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'clear' }) })}
        onUpdateAlert={updateAlert}
      />

      <LiveLogPanel items={liveLogItems} />

      <WorkingSessionsPanel sessions={sessions.working_sessions || []} />

      {/* KPI Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard
          title="Tageskosten"
          value={formatCost(totalCostToday)}
          subtitle={`${totalCallsToday} API-Aufrufe`}
          icon={<DollarSign className="w-5 h-5" />}
          color="from-emerald-500 to-teal-500"
        />
        <KPICard
          title="Jules Sessions"
          value={String(activeJulesSessions)}
          subtitle="in progress (Vorce)"
          icon={<Activity className="w-5 h-5" />}
          color="from-purple-500 to-violet-500"
        />
        <KPICard
          title="Open PRs"
          value={String(openPRs)}
          subtitle={`${conflictingPRs} mit Konflikten`}
          icon={<GitPullRequest className="w-5 h-5" />}
          color="from-blue-500 to-cyan-500"
        />
        <KPICard
          title="Abgeschlossen"
          value={String(sessions.completed_this_session?.length || 0)}
          subtitle="diese Session"
          icon={<TrendingUp className="w-5 h-5" />}
          color="from-amber-500 to-orange-500"
        />
      </div>

      {/* Provider Quota Overview + Chart */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Chart */}
        <div className="lg:col-span-2 glass-card p-6">
          <h3 className="text-lg font-semibold text-slate-200 mb-4">Provider-Nutzung Heute</h3>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData} barCategoryGap="20%">
                <XAxis dataKey="name" tick={{ fill: '#94a3b8', fontSize: 11 }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fill: '#94a3b8', fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip
                  contentStyle={{
                    background: 'rgba(15, 23, 42, 0.95)',
                    border: '1px solid rgba(139, 92, 246, 0.3)',
                    borderRadius: '12px',
                    color: '#e2e8f0',
                    fontSize: '13px',
                  }}
                  formatter={(value: number, _name: string, props: any) => [
                    `${value} / ${props.payload.limit}`,
                    'Aufrufe'
                  ]}
                />
                <Bar dataKey="calls" radius={[6, 6, 0, 0]}>
                  {chartData.map((entry, idx) => (
                    <Cell key={idx} fill={entry.color} fillOpacity={0.8} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Provider Cards */}
        <div className="space-y-3 max-h-[360px] overflow-y-auto pr-1">
          {providerEntries.filter(([, p]) => p.enabled).map(([key, provider]) => {
            const usage = provider.usage_today?.calls || 0;
            const limit = provider.daily_limit;
            const pct = limit > 0 ? Math.min((usage / limit) * 100, 100) : 0;
            const cost = provider.usage_today?.estimated_cost_usd || 0;
            const color = PROVIDER_COLORS[key] || '#8b5cf6';
            return (
              <div key={key} className="glass-card p-4 hover:border-slate-600/70 transition-all duration-200">
                <div className="flex justify-between items-center mb-2">
                  <span className="text-sm font-medium text-slate-200">{PROVIDER_LABELS[key] || key}</span>
                  <span className="text-xs text-slate-400">{usage}/{limit}</span>
                </div>
                <div className="w-full bg-slate-900/60 rounded-full h-2 mb-2">
                  <div
                    className="h-2 rounded-full transition-all duration-500"
                    style={{ width: `${pct}%`, background: color }}
                  />
                </div>
                <div className="flex justify-between items-center text-xs text-slate-500">
                  <span>{formatCost(cost)}</span>
                  <span>{pct.toFixed(0)}%</span>
                </div>
              </div>
            );
          })}
        </div>
      </div>

    </div>
  );
}

function formatNextRun(seconds?: number): string {
  if (seconds === undefined || seconds === null) return 'N/A';
  if (seconds <= 0) return 'jetzt faellig';
  const mins = Math.round(seconds / 60);
  if (mins < 60) return `in ${mins} min`;
  return `in ${Math.round((mins / 60) * 10) / 10} h`;
}

function getEscalationStep(alert: NonNullable<ActiveSessions['decisions_pending']>[number]) {
  if (alert.owner === 'user' || alert.process_stage === 'user_decision' || alert.escalation_level === 'user') return 2;
  if (alert.owner === 'alpha_ceo' || alert.process_stage?.startsWith('alpha') || alert.escalation_level === 'alpha') return 1;
  return 0;
}

function EscalationProcess({ alert }: { alert: NonNullable<ActiveSessions['decisions_pending']>[number] }) {
  const activeStep = getEscalationStep(alert);
  const steps = [
    { label: 'Beta Remediation', sub: alert.remediation_result || 'Audit-Fund' },
    { label: 'Alpha CEO', sub: alert.alpha_response ? 'Plan vorhanden' : 'Planning prueft' },
    { label: 'User', sub: alert.user_response ? 'Antwort vorhanden' : alert.owner === 'user' ? 'Entscheidung offen' : 'nicht erreicht' },
  ];

  return (
    <div className="grid grid-cols-3 gap-2 my-3">
      {steps.map((step, idx) => (
        <div key={step.label} className={`rounded border px-2 py-1.5 ${
          idx < activeStep ? 'bg-emerald-500/10 text-emerald-300 border-emerald-500/25' :
          idx === activeStep ? 'bg-amber-500/15 text-amber-200 border-amber-500/35' :
          'bg-slate-950/50 text-slate-500 border-slate-800'
        }`}>
          <div className="text-[10px] font-bold truncate">{step.label}</div>
          <div className="text-[9px] opacity-80 truncate">{step.sub}</div>
        </div>
      ))}
    </div>
  );
}

function AuditPanel({ auditResult, audit, alerts, onClear, onUpdateAlert }: {
  auditResult?: AuditResult;
  audit: any;
  alerts: NonNullable<ActiveSessions['decisions_pending']>;
  onClear: () => void;
  onUpdateAlert: (action: string, id: string, response?: string) => void;
}) {
  const hasAudit = Boolean(auditResult?.response || audit);
  const issuesFound = audit?.issues_found === true;
  const action = audit?.action || 'none';
  const borderClass = alerts.length > 0 || action === 'escalate'
    ? 'border-rose-500/30 shadow-lg shadow-rose-500/10'
    : issuesFound
      ? 'border-amber-500/30'
      : 'border-emerald-500/20';

  return (
    <div className={`glass-card p-6 border ${borderClass}`}>
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-3 mb-4">
        <div>
          <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
            <AlertCircle className={`w-5 h-5 ${alerts.length > 0 ? 'text-rose-400' : issuesFound ? 'text-amber-300' : 'text-emerald-300'}`} />
            Audit & Eskalationen
          </h3>
          <p className="text-xs text-slate-500 mt-1">
            Letztes Audit: {auditResult?.updated_at ? timeAgo(auditResult.updated_at) : hasAudit ? 'vorhanden' : 'noch kein Ergebnis'} · Offene Eskalationen: {alerts.length}
          </p>
        </div>
        {alerts.length > 0 && (
          <button
            onClick={onClear}
            className="text-xs px-3 py-1.5 rounded-lg bg-rose-500/20 text-rose-300 hover:bg-rose-500/30 border border-rose-500/30 transition-colors flex items-center gap-2"
            title="Alle Eskalationen löschen"
          >
            <XCircle className="w-4 h-4" />
            Clear
          </button>
        )}
      </div>

      <div className="rounded-lg border border-slate-800 bg-slate-950/45 p-4">
        <div className="flex flex-wrap items-center gap-2 mb-3">
          <span className={`px-2 py-1 rounded border text-[11px] font-bold ${
            issuesFound ? 'bg-amber-500/15 text-amber-300 border-amber-500/30' : 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
          }`}>
            {issuesFound ? 'ISSUES_FOUND' : 'NO_CRITICAL_ISSUES'}
          </span>
          <span className="px-2 py-1 rounded border text-[11px] font-bold bg-slate-900 text-slate-300 border-slate-700">
            ACTION: {String(action).toUpperCase()}
          </span>
        </div>

        {audit?.remediation_command ? (
          <div className="mb-3">
            <div className="text-[11px] uppercase text-slate-500 mb-1">Remediation</div>
            <pre className="text-xs text-amber-100 bg-amber-500/10 border border-amber-500/20 rounded p-2 overflow-x-auto whitespace-pre-wrap">{audit.remediation_command}</pre>
          </div>
        ) : null}

        {audit?.dashboard_escalation ? (
          <div>
            <div className="text-[11px] uppercase text-slate-500 mb-1">Audit-Eskalation</div>
            <p className="text-sm text-rose-100/85 whitespace-pre-wrap">{audit.dashboard_escalation}</p>
          </div>
        ) : (
          <p className="text-sm text-slate-400">
            {hasAudit ? 'Kein Dashboard-Eskalationstext im letzten Audit-Ergebnis.' : 'Noch kein Beta-CEO-Audit-Ergebnis vorhanden.'}
          </p>
        )}
      </div>

      {alerts.length > 0 && (
        <div className="space-y-3 mt-4">
          {alerts.map((alert, idx) => {
            const id = alert.id || String(idx);
            return (
              <div key={id} className="bg-rose-500/10 border border-rose-500/20 rounded-lg p-4">
                <div className="flex items-center justify-between mb-2">
                  <div className="min-w-0">
                    <span className="font-semibold text-rose-300">{alert.topic}</span>
                    <div className="text-[11px] text-rose-300/60">
                      Owner: {alert.owner || 'alpha_ceo'} · Status: {alert.status || 'open'} · Stufe: {alert.process_stage || 'alpha_review'} · {timeAgo(alert.created_at)}
                    </div>
                  </div>
                  <button
                    onClick={() => onUpdateAlert('remove', id)}
                    className="p-1.5 rounded text-rose-300 hover:bg-rose-500/20"
                    title="Eskalation löschen"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
                <EscalationProcess alert={alert} />
                <p className="text-sm text-rose-200/80 whitespace-pre-wrap">{alert.context}</p>
                {(alert.remediation_command || alert.remediation_result || alert.alpha_response || alert.user_escalation_reason) && (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-2 mt-3 text-xs">
                    {alert.remediation_command && (
                      <div className="rounded border border-amber-500/20 bg-amber-500/10 p-2">
                        <div className="text-[10px] uppercase text-amber-300/70 mb-1">Beta Remediation</div>
                        <div className="text-amber-100/85 whitespace-pre-wrap">{alert.remediation_command}</div>
                        {alert.remediation_result && <div className="mt-1 text-amber-200/60">{alert.remediation_result}</div>}
                      </div>
                    )}
                    {alert.alpha_response && (
                      <div className="rounded border border-cyan-500/20 bg-cyan-500/10 p-2">
                        <div className="text-[10px] uppercase text-cyan-300/70 mb-1">Alpha CEO Plan</div>
                        <div className="text-cyan-100/85 whitespace-pre-wrap">{alert.alpha_response}</div>
                      </div>
                    )}
                    {alert.user_escalation_reason && (
                      <div className="rounded border border-rose-500/25 bg-rose-500/10 p-2 md:col-span-2">
                        <div className="text-[10px] uppercase text-rose-300/70 mb-1">Grund fuer User-Eskalation</div>
                        <div className="text-rose-100/85 whitespace-pre-wrap">{alert.user_escalation_reason}</div>
                      </div>
                    )}
                  </div>
                )}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2 mt-3">
                  <AlertResponseBox
                    label="Alpha CEO Antwort"
                    value={alert.alpha_response || ''}
                    onSubmit={(text) => onUpdateAlert('alpha-response', id, text)}
                  />
                  <AlertResponseBox
                    label="User Antwort"
                    value={alert.user_response || ''}
                    onSubmit={(text) => onUpdateAlert('user-response', id, text)}
                  />
                </div>
                {alert.owner !== 'user' && alert.alpha_response && (
                  <button
                    onClick={() => onUpdateAlert('escalate-user', id, 'Alpha CEO Antwort war nicht zielfuehrend; User-Entscheidung erforderlich.')}
                    className="mt-2 px-2 py-1 text-[11px] rounded bg-rose-500/15 text-rose-200 border border-rose-500/25"
                  >
                    An User eskalieren
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function RunCard({ title, lastAt, nextAt, nextInSeconds, interval, cancelled, note, onCancel, onNote }: {
  title: string;
  lastAt?: string;
  nextAt?: string;
  nextInSeconds?: number;
  interval: string;
  cancelled?: boolean;
  note?: string;
  onCancel: () => void;
  onNote: (note: string) => void;
}) {
  const [draft, setDraft] = useState(note || '');
  return (
    <div className="glass-card p-5">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
          <CalendarClock className="w-4 h-4 text-cyan-400" />
          {title}
        </h3>
        <span className={`text-[11px] px-2 py-1 rounded border ${cancelled ? 'bg-rose-500/20 text-rose-300 border-rose-500/30' : 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'}`}>
          {cancelled ? 'cancelled' : formatNextRun(nextInSeconds)}
        </span>
      </div>
      <div className="grid grid-cols-2 gap-3 mt-4 text-xs text-slate-400">
        <div>
          <div className="text-slate-500">Letzter Run</div>
          <div className="text-slate-200">{lastAt ? timeAgo(lastAt) : 'N/A'}</div>
        </div>
        <div>
          <div className="text-slate-500">Naechster Run</div>
          <div className="text-slate-200">{nextAt ? new Date(nextAt).toLocaleTimeString() : 'N/A'} · {interval}</div>
        </div>
      </div>
      <div className="mt-4 flex gap-2">
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Info fuer kommenden Run"
          className="flex-1 min-w-0 px-3 py-2 text-xs bg-slate-950/80 border border-slate-700 rounded text-slate-200 placeholder-slate-500"
        />
        <button onClick={() => onNote(draft)} className="px-3 py-2 text-xs rounded border border-cyan-500/30 bg-cyan-500/15 text-cyan-300 flex items-center gap-1">
          <MessageSquare className="w-3.5 h-3.5" />
          Info
        </button>
        <button onClick={onCancel} className="px-3 py-2 text-xs rounded border border-rose-500/30 bg-rose-500/15 text-rose-300 flex items-center gap-1">
          <Ban className="w-3.5 h-3.5" />
          {cancelled ? 'Aktivieren' : 'Cancel'}
        </button>
      </div>
    </div>
  );
}

function AlertResponseBox({ label, value, onSubmit }: { label: string; value: string; onSubmit: (text: string) => void }) {
  const [text, setText] = useState(value);
  return (
    <div>
      <label className="block text-[11px] text-rose-300/70 mb-1">{label}</label>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        rows={3}
        className="w-full px-2 py-1.5 text-xs bg-slate-950/70 border border-rose-500/20 rounded text-slate-200"
      />
      <button onClick={() => onSubmit(text)} className="mt-1 px-2 py-1 text-[11px] rounded bg-rose-500/15 text-rose-200 border border-rose-500/25">
        Speichern
      </button>
    </div>
  );
}

function LiveLogPanel({ items }: { items: Array<{ time: string; message: string; level: string }> }) {
  const hasProblems = items.some(item => item.level === 'error' || item.level === 'warn');
  return (
    <div className={`glass-card p-5 border ${hasProblems ? 'border-amber-500/25' : 'border-slate-800'}`}>
      <div className="flex items-center justify-between gap-3 mb-3">
        <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
          <Terminal className="w-4 h-4 text-emerald-400" />
          Live-Log
        </h3>
        <span className={`text-[11px] px-2 py-1 rounded border ${
          hasProblems ? 'bg-amber-500/15 text-amber-300 border-amber-500/30' : 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
        }`}>
          {hasProblems ? 'Hinweise' : 'OK'}
        </span>
      </div>
      <div className="space-y-1.5 max-h-64 overflow-y-auto pr-1">
        {items.length === 0 ? (
          <div className="text-xs text-slate-500 rounded border border-slate-800 bg-slate-950/40 px-3 py-2">
            Noch keine Live-Logs vorhanden.
          </div>
        ) : (
          items.map((item, idx) => {
            const levelClass =
              item.level === 'error' ? 'bg-rose-500/10 text-rose-200 border-rose-500/25' :
              item.level === 'warn' ? 'bg-amber-500/10 text-amber-200 border-amber-500/25' :
              item.level === 'ok' ? 'bg-emerald-500/10 text-emerald-200 border-emerald-500/20' :
              'bg-slate-950/45 text-slate-300 border-slate-800';
            return (
              <div key={`${item.time}-${idx}`} className={`grid grid-cols-[4.5rem_1fr] gap-2 rounded border px-3 py-2 text-xs ${levelClass}`}>
                <span className="font-mono text-[11px] opacity-70">{item.time || '--:--:--'}</span>
                <span className="truncate" title={item.message}>{item.message}</span>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}

function WorkingSessionsPanel({ sessions }: { sessions: any[] }) {
  const counts = sessions.reduce((acc, item) => {
    const status = String(item.status || 'UNKNOWN').toUpperCase();
    acc[status] = (acc[status] || 0) + 1;
    return acc;
  }, {} as Record<string, number>);
  const recent = [...sessions].slice(-8).reverse();

  return (
    <div className="glass-card p-5 border border-slate-800">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-3 mb-3">
        <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
          <Activity className="w-4 h-4 text-cyan-400" />
          Working Sessions
        </h3>
        <div className="flex flex-wrap gap-2 text-[11px]">
          {['QUEUED', 'RUNNING', 'COMPLETED', 'FAILED'].map(status => (
            <span key={status} className={`px-2 py-1 rounded border ${
              status === 'FAILED' ? 'bg-rose-500/15 text-rose-300 border-rose-500/25' :
              status === 'RUNNING' ? 'bg-cyan-500/15 text-cyan-300 border-cyan-500/25' :
              status === 'COMPLETED' ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/25' :
              'bg-slate-900 text-slate-300 border-slate-700'
            }`}>
              {status}: {counts[status] || 0}
            </span>
          ))}
        </div>
      </div>
      {recent.length === 0 ? (
        <div className="text-xs text-slate-500 rounded border border-slate-800 bg-slate-950/40 px-3 py-2">
          Noch keine Working Sessions geplant.
        </div>
      ) : (
        <div className="space-y-1.5 max-h-56 overflow-y-auto pr-1">
          {recent.map((item, idx) => {
            const status = String(item.status || 'UNKNOWN').toUpperCase();
            return (
              <div key={item.id || idx} className="grid grid-cols-[5rem_1fr_8rem] gap-2 rounded border border-slate-800 bg-slate-950/45 px-3 py-2 text-xs text-slate-300">
                <span className="font-mono text-slate-500">#{item.issue_number || '-'}</span>
                <span className="truncate" title={item.issue_title || item.prompt_hint || ''}>{item.issue_title || item.prompt_hint || 'Working Session'}</span>
                <span className={`text-right font-semibold ${
                  status === 'FAILED' ? 'text-rose-300' :
                  status === 'RUNNING' ? 'text-cyan-300' :
                  status === 'COMPLETED' ? 'text-emerald-300' :
                  'text-slate-400'
                }`}>
                  {status}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function KPICard({ title, value, subtitle, icon, color }: {
  title: string; value: string; subtitle: string; icon: React.ReactNode; color: string;
}) {
  return (
    <div className="glass-card-hover p-5">
      <div className="flex items-center justify-between mb-3">
        <span className="text-sm text-slate-400">{title}</span>
        <div className={`w-9 h-9 rounded-lg bg-gradient-to-br ${color} flex items-center justify-center opacity-80`}>
          {icon}
        </div>
      </div>
      <div className="text-2xl font-bold text-white">{value}</div>
      <p className="text-xs text-slate-500 mt-1">{subtitle}</p>
    </div>
  );
}
