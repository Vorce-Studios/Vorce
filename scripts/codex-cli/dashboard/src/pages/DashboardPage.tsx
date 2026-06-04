import { useState } from 'react';
import { Activity, Zap, Clock, AlertCircle, XCircle, Trash2, CalendarClock, Ban, MessageSquare, Terminal } from 'lucide-react';
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
  onRefresh?: () => void;
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

function normalizeAuditText(value?: string): string {
  if (!value) return '';
  const oldQaLabel = ['Beta', 'CEO'].join(' ');
  const oldQaLabelAlt = ['CEO', 'Beta'].join(' ');
  const oldCeoLabel = ['Alpha', 'CEO'].join(' ');
  const oldCeoLabelAlt = ['CEO', 'Alpha'].join(' ');
  return value
    .replace(new RegExp(oldQaLabel, 'gi'), 'QA-Auditor')
    .replace(new RegExp(oldQaLabelAlt, 'gi'), 'QA-Auditor')
    .replace(new RegExp(oldCeoLabel, 'gi'), 'CEO')
    .replace(new RegExp(oldCeoLabelAlt, 'gi'), 'CEO')
    .replace(/beta_/gi, 'qa_');
}

function shortText(value?: string, max = 420): string {
  const text = normalizeAuditText(value).trim();
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1).trim()}...`;
}

function auditOwnerLabel(owner?: string): string {
  const value = (owner || '').toLowerCase();
  if (value === 'user') return 'Du';
  if (value.includes('alpha') || value === 'ceo') return 'CEO';
  return 'QA-Auditor';
}

function auditStageLabel(alert: any): string {
  const owner = auditOwnerLabel(alert.owner);
  if (owner === 'Du' || alert.escalation_level === 'user') return 'Wartet auf deine Entscheidung';
  if (owner === 'CEO') return 'CEO-Sondersession';
  return 'QA-Auditor repariert';
}

async function updateAuditAlert(action: string, id: string, response?: string) {
  await fetch('/api/alerts', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, id, response }),
  });
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

function formatNextRun(seconds?: number): string {
  if (typeof seconds !== 'number' || seconds <= 0) return 'N/A';
  if (seconds < 60) return `in ${seconds}s`;
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `in ${mins}m ${secs}s`;
}

export default function DashboardPage({ registry, sessions, auditResult, liveLog, onRefresh }: Props) {
  const providers = registry.providers || {};
  const providerEntries = Object.entries(providers);

  const scheduler = sessions.scheduler;
  const runControl = sessions.run_control || {};
  const liveLogItems = getLiveLogItems(liveLog);
  const audit = parseAuditResult(auditResult);

  const sendRunControl = async (type: 'planning' | 'monitoring', action: string, note?: string) => {
    await fetch('/api/run-control', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, action, note }),
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

      {/* Eskalationen (Beta CEO Alerts) */}
      {sessions.decisions_pending && sessions.decisions_pending.length > 0 && (
        <div className="glass-card p-6 border border-rose-500/30 shadow-lg shadow-rose-500/10">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-bold text-rose-400 flex items-center gap-2">
              <AlertCircle className="w-5 h-5" />
              Audit Alerts ({sessions.decisions_pending.length})
            </h3>
            <button
              onClick={async () => {
                await updateAuditAlert('clear', 'all');
                onRefresh?.();
              }}
              className="text-xs px-3 py-1.5 rounded-lg bg-rose-500/20 text-rose-300 hover:bg-rose-500/30 border border-rose-500/30 transition-colors flex items-center gap-2"
              title="Alle Audit Alerts löschen"
            >
              <XCircle className="w-4 h-4" />
              Alle löschen
            </button>
          </div>
          <div className="space-y-3">
            {sessions.decisions_pending.map((alert: any, idx) => {
              const id = alert.id || String(idx);
              const owner = auditOwnerLabel(alert.owner);
              const userStage = owner === 'Du' || alert.escalation_level === 'user';
              const ceoStage = owner === 'CEO' || alert.status === 'alpha_action_proposed' || alert.alpha_response;
              const activeStep = userStage ? 2 : ceoStage ? 1 : 0;
              return (
              <div key={id} className="bg-slate-950/50 border border-rose-500/20 rounded-lg p-4">
                <div className="flex flex-wrap items-start justify-between gap-3 mb-3">
                  <div>
                    <div className="font-semibold text-rose-200">{normalizeAuditText(alert.topic || 'QA-Auditor Alert')}</div>
                    <div className="text-xs text-rose-300/70 mt-0.5">
                      Zuständig: {owner} · {auditStageLabel(alert)} · {timeAgo(alert.created_at)}
                    </div>
                  </div>
                  <button
                    onClick={async () => {
                      await updateAuditAlert('remove', id);
                      onRefresh?.();
                    }}
                    className="p-1.5 rounded-md bg-slate-900 text-slate-400 hover:text-rose-300 border border-slate-700"
                    title="Audit Alert löschen"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>

                <div className="grid grid-cols-3 gap-2 mb-3">
                  {['QA-Auditor', 'CEO', 'Du'].map((label, stepIdx) => (
                    <div key={label} className={`h-1.5 rounded-full ${stepIdx <= activeStep ? 'bg-rose-400' : 'bg-slate-800'}`} title={label} />
                  ))}
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-3 gap-3 text-sm">
                  <div className="rounded-md bg-slate-900/70 border border-slate-800 p-3">
                    <div className="uppercase text-rose-300/70 text-[10px] mb-1">Problem</div>
                    <div className="text-slate-200 whitespace-pre-wrap">{shortText(alert.context)}</div>
                  </div>
                  <div className="rounded-md bg-slate-900/70 border border-slate-800 p-3">
                    <div className="uppercase text-amber-300/70 text-[10px] mb-1">QA-Auditor Versuch</div>
                    <div className="text-slate-300 whitespace-pre-wrap">
                      {shortText(alert.remediation_command || alert.remediation_result || 'Noch kein dokumentierter Reparaturversuch.')}
                    </div>
                  </div>
                  <div className="rounded-md bg-slate-900/70 border border-slate-800 p-3">
                    <div className="uppercase text-cyan-300/70 text-[10px] mb-1">CEO Sondersession</div>
                    <div className="text-slate-300 whitespace-pre-wrap">
                      {shortText(alert.alpha_response || (ceoStage ? 'CEO-Sondersession geplant.' : 'Noch nicht erreicht.'))}
                    </div>
                  </div>
                </div>

                {alert.user_escalation_reason && (
                  <div className="mt-3 rounded-md border border-orange-500/30 bg-orange-500/10 p-3 text-sm text-orange-200">
                    {shortText(alert.user_escalation_reason)}
                  </div>
                )}

                {!userStage && ceoStage && (
                  <div className="mt-3 flex justify-end">
                    <button
                      onClick={async () => {
                        await updateAuditAlert('escalate-user', id, 'CEO Sondersession konnte die Ursache nicht beheben. Deine Entscheidung ist erforderlich.');
                        onRefresh?.();
                      }}
                      className="text-xs px-3 py-1.5 rounded-lg bg-orange-500/20 text-orange-200 hover:bg-orange-500/30 border border-orange-500/30"
                    >
                      An mich eskalieren
                    </button>
                  </div>
                )}
              </div>
            )})}
          </div>
        </div>
      )}

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

function JulesStateBadge({ state }: { state: string }) {
  const configs: Record<string, { bg: string; text: string; label: string }> = {
    'IN_PROGRESS': { bg: 'bg-blue-500/20', text: 'text-blue-400', label: 'In Progress' },
    'AWAITING_USER_FEEDBACK': { bg: 'bg-amber-500/20', text: 'text-amber-400', label: 'Feedback' },
    'COMPLETED': { bg: 'bg-emerald-500/20', text: 'text-emerald-400', label: 'Fertig' },
    'FAILED': { bg: 'bg-red-500/20', text: 'text-red-400', label: 'Fehlgeschlagen' },
  };
  const cfg = configs[state] || { bg: 'bg-slate-500/20', text: 'text-slate-400', label: state };
  return (
    <span className={`badge ${cfg.bg} ${cfg.text}`}>{cfg.label}</span>
  );
}
