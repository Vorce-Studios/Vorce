import { useState } from 'react';
import { Activity, DollarSign, GitPullRequest, Zap, Clock, TrendingUp, AlertCircle, XCircle, CalendarClock, Ban, MessageSquare, Terminal, Play, CheckCircle, Trash2 } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';
import type { QuotaRegistry, ActiveSessions, PullRequest, GitHubIssue, AuditResult } from '../types';
import DeliberationPanel from './DeliberationPanel';
import { RunHierarchyView } from '../components/RunHierarchyView';
import type { RunSummary } from '../types';

interface Props {
  registry: QuotaRegistry;
  sessions: ActiveSessions;
  pullRequests: PullRequest[];
  issues: GitHubIssue[];
  julesSessions?: any[];
  auditResult?: AuditResult;
  runHierarchy?: any;
  runSummary?: RunSummary;
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
  if (Number.isNaN(then.getTime())) return 'N/A';
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
  return value
    .replace(/CEO ALPHA/gi, 'CEO')
    .replace(/CEO BETA/gi, 'QA Manager')
    .replace(/CEO-ALPHA/gi, 'CEO')
    .replace(/CEO-BETA/gi, 'QA-Manager')
    .replace(/QA-Auditor/gi, 'QA Manager')
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
  if (value === 'qa-manager' || value === 'beta') return 'QA Manager';
  return 'CEO';
}

function auditStageLabel(alert: any): string {
  const owner = auditOwnerLabel(alert.owner);
  if (owner === 'Du' || alert.escalation_level === 'user') return 'Wartet auf deine Entscheidung';
  if (owner === 'CEO') return 'CEO-Sondersession';
  return 'QA Manager repariert';
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

function formatNextRun(seconds?: number): string {
  if (typeof seconds !== 'number' || seconds <= 0) return 'N/A';
  if (seconds < 60) return `in ${seconds}s`;
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `in ${mins}m ${secs}s`;
}

export default function DashboardPage({ registry, sessions, pullRequests, julesSessions, auditResult, runHierarchy, runSummary }: Props) {
  const providers = registry.providers || {};
  const providerEntries = Object.entries(providers);

  const runControl = sessions.run_control || {};
  const audit = parseAuditResult(auditResult);
  const [showCommentModal, setShowCommentModal] = useState<string | null>(null);
  const [commentDraft, setCommentDraft] = useState<string>('');
  const [expandedRunNodes, setExpandedRunNodes] = useState<Set<string>>(new Set());

  const activeAlerts = sessions.decisions_pending?.filter(a => a.status !== 'closed' && a.status !== 'ignored') || [];

  const sendRunControl = async (mainRun: string, action: string, note?: string) => {
    await fetch('/api/run-control', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ main_run: mainRun, action, note }),
    });
  };

  const triggerMainRun = async (mainRun: string) => {
    await fetch('/api/trigger-main-run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ main_run: mainRun }),
    });
  };

  const handleRunNodeClick = (runState: any) => {
    // Log the run state details for debugging
    console.log('Run state clicked:', runState);
    // In a real implementation, this would open a detailed view or modal
  };

  const handleSelectFile = (filePath: string) => {
    if (!filePath) return;
    console.log('Opening JSON file:', filePath);
    alert(`Öffne JSON-Datei: ${filePath}`);
  };

  const toggleRunNode = (nodeId: string) => {
    setExpandedRunNodes(prev => {
      const newSet = new Set(prev);
      if (newSet.has(nodeId)) {
        newSet.delete(nodeId);
      } else {
        newSet.add(nodeId);
      }
      return newSet;
    });
  };

  const totalCostToday = providerEntries.reduce((sum, [, p]) => sum + (p.usage_today?.estimated_cost_usd || 0), 0);
  const totalCallsToday = providerEntries.reduce((sum, [, p]) => sum + (p.usage_today?.calls || 0), 0);

  const julesUsage = providers.jules?.usage_today || {};
  const julesArray = Array.isArray(julesSessions) ? julesSessions : [];
  const runningJulesSessions = julesArray.filter(s =>
      String(s.repo || '') === 'Vorce-Studios/Vorce' &&
      ['IN_PROGRESS', 'PLANNING', 'QUEUED', 'AWAITING_PLAN_APPROVAL'].includes(String(s.state || ''))
  ).length;
  const waitingJulesSessions = julesArray.filter(s =>
      String(s.repo || '') === 'Vorce-Studios/Vorce' &&
      ['AWAITING_USER_FEEDBACK', 'AWAITING_USER_FEEDBACK_CI_OR_BLOCKER', 'PAUSED'].includes(String(s.state || ''))
    ).length || Number(julesUsage.scoped_live_waiting_sessions ?? julesUsage.pending_sessions ?? 0);
  const activeJulesSessions = julesSessions
    ? runningJulesSessions + waitingJulesSessions
    : Number(julesUsage.scoped_live_capacity_sessions ?? julesUsage.active_sessions ?? 0);

  // Filter PRs that are OPEN and NOT a Draft and belong to Vorce repo
  const prArray = Array.isArray(pullRequests) ? pullRequests : [];
  const openPRs = prArray.filter(pr => pr.repo?.includes('Vorce') && pr.state === 'OPEN' && pr.isDraft !== true).length;
  const conflictingPRs = prArray.filter(pr => pr.repo?.includes('Vorce') && pr.state === 'OPEN' && pr.isDraft !== true && pr.mergeable === 'CONFLICTING').length;
  const hierarchyMainCount = runHierarchy?.main_runs?.length || 0;
  const hierarchySubCount = runHierarchy?.main_runs?.reduce((sum: number, main: any) => sum + (main.sub_runs?.length || 0), 0) || 0;
  const hierarchyPartCount = runHierarchy?.main_runs?.reduce(
    (sum: number, main: any) => sum + (main.sub_runs || []).reduce((subSum: number, sub: any) => subSum + (sub.part_runs?.length || 0), 0),
    0
  ) || 0;

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
              <h2 className="text-xl font-bold gradient-text">Vorce-Factory</h2>
              <p className="text-sm text-slate-400 flex items-center gap-2 mt-0.5">
                <span className="status-dot-active" />
                Aktiv seit {timeAgo(sessions.started_at || '')}
                <span className="text-slate-600">•</span>
                Session: {sessions.session_id || 'N/A'}
              </p>
            </div>
          </div>
          <div className="text-right text-sm text-slate-400">
            <div className="flex items-center gap-1.5 justify-end">
              <Clock className="w-3.5 h-3.5" />
              Letzter Heartbeat: {timeAgo(sessions.last_heartbeat || '')}
            </div>
            {auditResult && (
              <div className="flex items-center gap-1.5 mt-1 justify-end">
                <AlertCircle className={`w-3.5 h-3.5 ${audit?.issues_found ? 'text-amber-400' : 'text-emerald-400'}`} />
                System-Audit: <span className={audit?.issues_found ? 'text-amber-300 font-semibold' : 'text-emerald-300 font-semibold'}>
                  {audit?.issues_found ? 'Auffälligkeiten' : 'Fehlerfrei'}
                </span>
                {auditResult.updated_at && <span className="text-[10px] text-slate-500">({timeAgo(auditResult.updated_at)})</span>}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Run Hierarchy View */}
      <div className="glass-card p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-slate-200 flex items-center gap-2">
            <Activity className="w-5 h-5" />
            Run-Hierarchie
          </h3>
          <span className="text-sm text-slate-400">
            {runHierarchy?.main_runs ? `${hierarchyMainCount} Main-Runs / ${hierarchySubCount} Sub-Runs / ${hierarchyPartCount} Part-Runs` : `${sessions.run_states?.length || 0} Runs`}
          </span>
        </div>
        <RunHierarchyView
          runHierarchy={runHierarchy}
          onNodeClick={handleRunNodeClick}
          expandedNodes={expandedRunNodes}
          onToggleNode={toggleRunNode}
          onSelectFile={handleSelectFile}
        />
      </div>

      {/* Audit Alert Box if issues found but no active decisions_pending */}
      {audit?.issues_found && (!sessions.decisions_pending || sessions.decisions_pending.length === 0) && (
        <div className="glass-card p-5 border border-amber-500/25 bg-amber-500/5">
          <div className="flex items-center gap-2 mb-2 text-amber-400 font-semibold text-sm">
            <AlertCircle className="w-4.5 h-4.5" />
            Letztes System-Audit meldete Handlungsbedarf
          </div>
          <p className="text-xs text-slate-300 whitespace-pre-wrap leading-relaxed">
            {normalizeAuditText(audit.dashboard_escalation || 'Es wurden Probleme beim letzten Systemlauf festgestellt.')}
          </p>
          {audit.remediation_command && (
            <div className="mt-3">
              <span className="text-[10px] uppercase tracking-wider font-semibold text-slate-500">Empfohlener Reparatur-Befehl:</span>
              <pre className="text-xs text-amber-200 bg-slate-950/60 border border-slate-800 rounded p-2.5 mt-1.5 font-mono overflow-x-auto select-all">
                {audit.remediation_command}
              </pre>
            </div>
          )}
        </div>
      )}

      {/* Audit Alerts */}
      {activeAlerts.length > 0 && (
        <div className="glass-card p-6 border border-rose-500/30 shadow-lg shadow-rose-500/10">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-bold text-rose-400 flex items-center gap-2">
              <AlertCircle className="w-5 h-5" />
              Audit Alerts ({activeAlerts.length})
            </h3>
            <button
              onClick={async () => {
                await fetch('/api/clear-alerts', { method: 'POST' });
              }}
              className="text-xs px-3 py-1.5 rounded-lg bg-rose-500/20 text-rose-300 hover:bg-rose-500/30 border border-rose-500/30 transition-colors flex items-center gap-2"
              title="Alle Audit Alerts löschen"
            >
              <XCircle className="w-4 h-4" />
              Alle löschen
            </button>
          </div>
          <div className="space-y-3">
            {activeAlerts.map((alert: any, idx) => {
              const id = alert.id || String(idx);
              const owner = auditOwnerLabel(alert.owner);
              const userStage = owner === 'Du' || alert.escalation_level === 'user';
              const ceoStage = owner === 'CEO' || alert.status === 'alpha_action_proposed' || alert.alpha_response;
              const activeStep = userStage ? 2 : ceoStage ? 1 : 0;
              return (
                <div key={id} className="bg-slate-950/50 border border-rose-500/20 rounded-lg p-4">
                  <div className="space-y-3">
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <div className="font-semibold text-rose-200">{normalizeAuditText(alert.topic || 'QA Manager Alert')}</div>
                        <div className="text-xs text-rose-300/70 mt-0.5">
                          Zuständig: {owner} · {auditStageLabel(alert)} · {timeAgo(alert.created_at)}
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        {alert.status === 'closed' && (
                          <span className="text-[10px] px-2 py-1 bg-emerald-500/20 text-emerald-300 rounded border border-emerald-500/30">
                            Geschlossen: {timeAgo(alert.closed_at || '')}
                          </span>
                        )}
                        {alert.status === 'ignored' && (
                          <span className="text-[10px] px-2 py-1 bg-amber-500/20 text-amber-300 rounded border border-amber-500/30">
                            Ignoriert: {timeAgo(alert.closed_at || '')}
                          </span>
                        )}
                        {!alert.status && (
                          <button
                            onClick={() => setShowCommentModal(id)}
                            className="p-1.5 rounded-md bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border border-emerald-500/30"
                            title="Alert schließen"
                          >
                            <CheckCircle className="w-4 h-4" />
                          </button>
                        )}
                        <button
                          onClick={async () => {
                            if (window.confirm('Diesen Alert wirklich komplett löschen?')) {
                              await updateAuditAlert('remove', id);
                              window.location.reload();
                            }
                          }}
                          className="p-1.5 rounded-md bg-rose-500/10 text-rose-400 hover:bg-rose-500/20 border border-rose-500/30"
                          title="Alert komplett löschen"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </div>

                    {alert.status === 'closed' && alert.user_comment && (
                      <div className="text-xs text-slate-500 bg-slate-900/40 rounded p-2">
                        <span className="text-slate-400 font-medium">Kommentar:</span> {alert.user_comment}
                      </div>
                    )}
                    {alert.status === 'ignored' && alert.user_comment && (
                      <div className="text-xs text-slate-500 bg-slate-900/40 rounded p-2">
                        <span className="text-slate-400 font-medium">Begründung:</span> {alert.user_comment}
                      </div>
                    )}
                  </div>

                  <div className="grid grid-cols-3 gap-2 mb-3">
                    {['QA Manager', 'CEO', 'Du'].map((label, stepIdx) => (
                      <div key={label} className={`h-1.5 rounded-full ${stepIdx <= activeStep ? 'bg-rose-400' : 'bg-slate-800'}`} title={label} />
                    ))}
                  </div>

                  <div className="grid grid-cols-1 lg:grid-cols-3 gap-3 text-sm">
                    <div className="rounded-md bg-slate-900/70 border border-slate-800 p-3">
                      <div className="uppercase text-rose-300/70 text-[10px] mb-1">Problem</div>
                      <div className="text-slate-200 whitespace-pre-wrap">{shortText(alert.context)}</div>
                    </div>
                    <div className="rounded-md bg-slate-900/70 border border-slate-800 p-3 flex flex-col">
                      <div className="uppercase text-amber-300/70 text-[10px] mb-1">QA Manager Versuch</div>
                      <div className="text-slate-300 whitespace-pre-wrap flex-1">
                        {shortText(alert.remediation_command || alert.remediation_result || 'Noch kein dokumentierter Reparaturversuch.')}
                      </div>
                      {alert.remediation_command && !alert.status && (
                        <button
                          onClick={() => {
                            // In einer echten Umgebung wuerde hier ein API-Call an den Autopilot gehen
                            window.alert('Manuelle Remediation gestartet: ' + alert.remediation_command);
                          }}
                          className="mt-2 text-[9px] px-2 py-1 rounded bg-amber-500/10 text-amber-300 hover:bg-amber-500/20 border border-amber-500/30 transition-colors self-start"
                        >
                          Befehl erneut ausführen
                        </button>
                      )}
                    </div>
                    <div className="rounded-md bg-slate-900/70 border border-slate-800 p-3 flex flex-col">
                      <div className="uppercase text-cyan-300/70 text-[10px] mb-1">CEO Sondersession</div>
                      <div className="text-slate-300 whitespace-pre-wrap flex-1">
                        {shortText(alert.alpha_response || (ceoStage ? 'CEO-Sondersession geplant.' : 'Noch nicht erreicht.'))}
                      </div>
                      {!ceoStage && !alert.status && (
                        <button
                          onClick={() => updateAuditAlert('escalate-ceo', id, 'Manuelle Eskalation an CEO zur Sondersession.')}
                          className="mt-2 text-[9px] px-2 py-1 rounded bg-cyan-500/10 text-cyan-300 hover:bg-cyan-500/20 border border-cyan-500/30 transition-colors self-start"
                        >
                          CEO Sondersession anfordern
                        </button>
                      )}
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
                        onClick={() => updateAuditAlert('escalate-user', id, 'CEO Sondersession konnte die Ursache nicht beheben. Deine Entscheidung ist erforderlich.')}
                        className="text-xs px-3 py-1.5 rounded-lg bg-orange-500/20 text-orange-200 hover:bg-orange-500/30 border border-orange-500/30"
                      >
                        An mich eskalieren
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Comment Modal */}
      {showCommentModal && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-slate-900 border border-slate-700 rounded-2xl max-w-md w-full p-6 shadow-2xl">
            <h3 className="text-lg font-semibold text-slate-100 mb-2">Alert schließen / Ignorieren</h3>
            <p className="text-sm text-slate-400 mb-4">Warum wird dieser Alert geschlossen oder ignoriert?</p>

            <textarea
              className="w-full h-24 px-3 py-2 text-sm bg-slate-950 border border-slate-700 rounded-lg text-slate-200 placeholder-slate-600 focus:ring-2 focus:ring-emerald-500/50 focus:border-emerald-500/50 resize-none"
              placeholder="z.B. PR #779 passt später wieder in die Namenskonvention, aktueller Workaround..."
              value={commentDraft}
              onChange={(e) => setCommentDraft(e.target.value)}
            />

            <div className="flex justify-end gap-2 mt-4">
              <button
                onClick={() => {
                  setShowCommentModal(null);
                  setCommentDraft('');
                }}
                className="px-4 py-2 text-sm rounded-lg bg-slate-800 text-slate-300 hover:bg-slate-700 border border-slate-600 transition-colors"
              >
                Abbrechen
              </button>
              <button
                onClick={async () => {
                  setShowCommentModal(null);
                  await updateAuditAlert('close-alert', showCommentModal, commentDraft || 'Manuell geschlossen');
                  window.location.reload();
                }}
                className="px-4 py-2 text-sm rounded-lg bg-emerald-600 text-white hover:bg-emerald-500 transition-colors"
              >
                Schließen
              </button>
              <button
                onClick={async () => {
                  setShowCommentModal(null);
                  await updateAuditAlert('ignore-alert', showCommentModal, commentDraft || 'Ignoriert (repeat-accept)');
                  window.location.reload();
                }}
                className="px-4 py-2 text-sm rounded-lg bg-amber-600 text-white hover:bg-amber-500 transition-colors"
              >
                Ignorieren & Memory
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Run control cards */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {(sessions.main_runs || []).map(run => (
          <RunCard
            key={run.name}
            title={run.label}
            status={run.status}
            lastAt={run.last_run_at || undefined}
            nextAt={run.next_run_at}
            nextInSeconds={run.next_run_in_seconds}
            interval={`${run.interval_minutes} min`}
            cancelled={run.control?.cancel_next}
            note={run.control?.note}
            summary={`${run.summary || ''} · ${run.sub_runs.length} konfigurierte Sub-Runs`}
            onRunNow={() => triggerMainRun(run.name)}
            onCancel={() => sendRunControl(run.name, run.control?.cancel_next ? 'uncancel-next' : 'cancel-next')}
            onNote={(note) => sendRunControl(run.name, 'note-next', note)}
          />
        ))}
      </div>

      {/* Run Summary & Working Sessions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <RunSummaryPanel summary={runSummary} />
        <WorkingSessionsPanel sessions={sessions.working_sessions || []} />
      </div>

      <ReviewQueuePanel queue={sessions.review_queue || []} />

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
          subtitle={`${runningJulesSessions} laufen, ${waitingJulesSessions} warten`}
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

      {/* Optimizer-Sessions Queue Widget */}
      <OptimizerQueuePanel
        queue={sessions.optimizer_queue}
        lastRun={sessions.optimizer_last_run}
        lastOptimizerAt={sessions.last_optimizer_analysis_at}
        forceRequestedAt={runControl.force_optimizer_requested_at}
      />

      {/* Dual-CEO Deliberation Panel */}
      <DeliberationPanel deliberations={sessions.deliberation_log || []} />
    </div>
  );
}

function getNextOptimizerRun(lastRun?: any, lastOptimizerAt?: string): string {
  if (lastRun?.next_run_at) return lastRun.next_run_at;
  if (!lastOptimizerAt) return '';
  const next = new Date(lastOptimizerAt);
  if (Number.isNaN(next.getTime())) return '';
  next.setHours(next.getHours() + 12);
  return next.toISOString();
}

function ReviewQueuePanel({ queue }: { queue: ActiveSessions['review_queue'] }) {
  const pending = queue.filter(item => item.review_status === 'pending');
  return (
    <div className="glass-card p-5 border border-slate-800">
      <div className="flex items-center justify-between gap-3 mb-4">
        <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
          <GitPullRequest className="text-emerald-400 w-4 h-4" />
          Claude Code Review Queue
        </h3>
        <span className="text-xs text-slate-400">{pending.length} ausstehend</span>
      </div>
      {pending.length === 0 ? (
        <div className="text-xs text-slate-500">Keine PRs warten auf Review.</div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
          {pending.map(item => (
            <a key={`${item.issue_number}-${item.pr_number}`} href={item.pr_url} target="_blank" rel="noreferrer"
              className="border border-slate-800 bg-slate-950/45 rounded p-3 hover:border-emerald-500/40 transition-colors">
              <div className="flex justify-between gap-3">
                <span className="text-sm font-medium text-slate-200">PR #{item.pr_number}</span>
                <span className="text-[11px] text-amber-300">pending</span>
              </div>
              <div className="text-xs text-slate-500 mt-1">Issue #{item.issue_number} · Review durch Claude Code</div>
            </a>
          ))}
        </div>
      )}
    </div>
  );
}

function OptimizerQueuePanel({ queue, lastRun, lastOptimizerAt, forceRequestedAt }: {
  queue?: any[];
  lastRun?: any;
  lastOptimizerAt?: string;
  forceRequestedAt?: string;
}) {
  const [loading, setLoading] = useState<string | null>(null);

  const handleAction = async (id: string, action: 'approve' | 'reject' | 'run-now') => {
    setLoading(id || action);
    try {
      await fetch('/api/optimizer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, id }),
      });
      window.location.reload();
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(null);
    }
  };

  const activeProposals = queue ? queue.filter(item => item.status !== 'APPROVED' && item.status !== 'REJECTED') : [];
  const lastProposals = Array.isArray(lastRun?.proposals) ? lastRun.proposals : [];
  const approvedChanges = Array.isArray(lastRun?.approved_changes) ? lastRun.approved_changes : [];
  const nextRunAt = getNextOptimizerRun(lastRun, lastOptimizerAt);

  return (
    <div className="glass-card p-5 border border-slate-800">
      <div className="flex flex-col md:flex-row md:items-start justify-between gap-3 mb-4">
        <div>
          <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
            <Zap className="text-amber-400 w-4 h-4" />
            Optimizer-Sessions
          </h3>
          <div className="mt-1 text-xs text-slate-500">
            Letzter Run: {lastRun?.ran_at ? timeAgo(lastRun.ran_at) : 'N/A'} · Nächster Run: {nextRunAt ? new Date(nextRunAt).toLocaleTimeString() : 'N/A'}
          </div>
          {forceRequestedAt && (
            <div className="mt-1 text-[11px] text-amber-300">
              Manueller Optimizer-Run angefordert: {timeAgo(forceRequestedAt)}
            </div>
          )}
        </div>
        <button
          disabled={loading !== null}
          onClick={() => handleAction('', 'run-now')}
          className="px-3 py-2 text-xs rounded border border-amber-500/30 bg-amber-500/15 text-amber-300 hover:bg-amber-500/25 disabled:opacity-50 transition-colors flex items-center gap-1.5"
          title="Optimizer beim nächsten Planning-Lauf erzwingen"
        >
          <Play className="w-3.5 h-3.5" />
          Jetzt ausführen
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
        <OptimizerList title={`Aktive Vorschläge (${activeProposals.length})`}>
          {activeProposals.length === 0 ? (
            <EmptyOptimizerText text="Keine offenen Optimierungsvorschläge." />
          ) : activeProposals.map((item) => (
            <OptimizerItem key={item.id} item={item}>
              <div className="flex justify-end gap-2 mt-3">
                <button
                  disabled={loading !== null}
                  onClick={() => handleAction(item.id, 'reject')}
                  className="px-3 py-1.5 rounded bg-rose-500/10 text-rose-300 border border-rose-500/30 hover:bg-rose-500/20 disabled:opacity-50 transition-colors"
                >
                  Ablehnen
                </button>
                <button
                  disabled={loading !== null}
                  onClick={() => handleAction(item.id, 'approve')}
                  className="px-3 py-1.5 rounded bg-emerald-500/10 text-emerald-300 border border-emerald-500/30 hover:bg-emerald-500/20 disabled:opacity-50 transition-colors"
                >
                  Freigeben
                </button>
              </div>
            </OptimizerItem>
          ))}
        </OptimizerList>

        <OptimizerList title={`Letzter Run (${lastProposals.length})`}>
          {lastProposals.length === 0 ? (
            <EmptyOptimizerText text={lastRun?.summary || 'Noch kein Optimizer-Run dokumentiert.'} />
          ) : lastProposals.map((item: any) => <OptimizerItem key={item.id || item.title} item={item} />)}
        </OptimizerList>

        <OptimizerList title={`Genehmigt (${approvedChanges.length})`}>
          {approvedChanges.length === 0 ? (
            <EmptyOptimizerText text="Noch keine genehmigten Optimizer-Änderungen." />
          ) : approvedChanges.map((item: any) => <OptimizerItem key={item.id || item.title} item={item} />)}
        </OptimizerList>
      </div>
    </div>
  );
}

function OptimizerList({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-slate-800 bg-slate-950/30 p-3 min-h-36">
      <div className="text-[11px] uppercase tracking-wide font-semibold text-slate-400 mb-2">{title}</div>
      <div className="space-y-3 max-h-[360px] overflow-y-auto pr-1">{children}</div>
    </div>
  );
}

function EmptyOptimizerText({ text }: { text: string }) {
  return <div className="text-xs text-slate-500 rounded border border-slate-800 bg-slate-950/40 px-3 py-2">{text}</div>;
}

function OptimizerItem({ item, children }: { item: any; children?: React.ReactNode }) {
  return (
    <div className="bg-slate-950/50 border border-slate-800 rounded-lg p-3 text-xs text-slate-300">
      <div className="flex justify-between items-start gap-3 mb-2">
        <div className="font-semibold text-slate-200 text-sm">{item.title}</div>
        {(item.created_at || item.approved_at) && (
          <span className="text-[10px] text-slate-500">{timeAgo(item.approved_at || item.created_at)}</span>
        )}
      </div>
      <div className="space-y-2">
        {item.description && <div><span className="text-slate-500 font-medium">Problem:</span> {item.description}</div>}
        {item.impact && <div><span className="text-emerald-400 font-medium">Auswirkung:</span> {item.impact}</div>}
        {item.proposed_action && <div><span className="text-cyan-400 font-medium">Aktion:</span> {item.proposed_action}</div>}
      </div>
      {children}
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

function RunCard({ title, status, lastAt, nextAt, nextInSeconds, interval, cancelled, note, summary, onRunNow, onCancel, onNote }: {
  title: string;
  status: string;
  lastAt?: string;
  nextAt?: string;
  nextInSeconds?: number;
  interval: string;
  cancelled?: boolean;
  note?: string;
  summary?: string;
  onRunNow: () => void;
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
          <span className="text-[10px] uppercase tracking-wide text-slate-500">{status}</span>
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
      <div className="mt-3 rounded border border-slate-800 bg-slate-950/40 px-3 py-2 text-xs text-slate-300 min-h-10">
        <div className="text-[10px] uppercase tracking-wide text-slate-500 mb-1">Letzte Tätigkeiten</div>
        {summary || 'Noch keine Zusammenfassung im State.'}
      </div>
      <div className="mt-4 flex gap-2">
        <button onClick={onRunNow} className="px-3 py-2 text-xs rounded border border-emerald-500/30 bg-emerald-500/15 text-emerald-300 flex items-center gap-1">
          <Play className="w-3.5 h-3.5" />
          Start
        </button>
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
            const detail = String(item.error || item.failure_reason || item.details || '').trim();
            return (
              <div key={item.id || idx} className="rounded border border-slate-800 bg-slate-950/45 px-3 py-2 text-xs text-slate-300">
                <div className="grid grid-cols-[5rem_1fr_8rem] gap-2 items-center">
                  <span className="font-mono text-slate-500">#{item.issue_number || '-'}</span>
                  <span className="truncate" title={item.issue_title || item.prompt_hint || ''}>{item.issue_title || item.prompt_hint || 'Working Session'}</span>
                  <div className="text-right">
                    <JulesStateBadge state={status} />
                  </div>
                </div>
                {detail && (
                  <div className="mt-1 pl-[5rem] text-[11px] text-rose-300/90 truncate" title={detail}>
                    {detail}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
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

function RunSummaryPanel({ summary }: { summary?: RunSummary }) {
  const recent = summary?.recent_runs || [];
  const stats24h = summary?.stats_24h || {};
  return (
    <div className="glass-card p-5 border border-slate-800">
      <div className="flex items-center justify-between gap-3 mb-4">
        <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
          <Activity className="text-cyan-400 w-4 h-4" />
          Run-Zusammenfassung
        </h3>
        <span className="text-xs text-slate-400">{recent.length} letzte Runs</span>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4 text-xs">
        <StatBox label="24h Runs" value={String(stats24h.runs_completed || 0)} />
        <StatBox label="24h Fallbacks" value={String(stats24h.fallbacks || 0)} />
        <StatBox label="24h reused" value={String(stats24h.sub_runs_reused || 0)} />
        <StatBox label="24h Dauer" value={`${Math.round((stats24h.avg_duration_ms || 0) / 1000)}s`} />
      </div>
      {recent.length === 0 ? (
        <div className="text-xs text-slate-500">Noch keine Run-History vorhanden.</div>
      ) : (
        <div className="space-y-2 max-h-[320px] overflow-y-auto pr-1">
          {recent.map((run) => (
            <div key={run.run_id} className="rounded-lg border border-slate-800 bg-slate-950/40 p-3">
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="text-sm font-medium text-slate-100 truncate">{run.main_run}</div>
                  <div className="text-[11px] text-slate-500">{run.status} • {run.result_summary}</div>
                </div>
                <div className="text-right text-[11px] text-slate-500">
                  <div>{run.duration_ms ? `${Math.round(run.duration_ms / 1000)}s` : 'N/A'}</div>
                  <div>{run.completed_at ? timeAgo(run.completed_at) : ''}</div>
                </div>
              </div>
              <div className="mt-2 grid grid-cols-4 gap-2 text-[10px] text-slate-400">
                <span>SUB {run.sub_runs.completed}/{run.sub_runs.failed}/{run.sub_runs.reused}</span>
                <span>PART {run.part_runs.completed}/{run.part_runs.failed}/{run.part_runs.reused}</span>
                <span>Fallbacks {run.fallbacks}</span>
                <span>Attempts {run.provider_attempts}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function StatBox({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-slate-800 bg-slate-950/30 p-2">
      <div className="text-[10px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className="text-sm text-slate-100 font-semibold">{value}</div>
    </div>
  );
}
