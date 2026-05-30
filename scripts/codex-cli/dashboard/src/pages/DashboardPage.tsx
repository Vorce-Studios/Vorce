import { Activity, DollarSign, GitPullRequest, Zap, Clock, TrendingUp, CheckCircle, AlertCircle } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';
import type { QuotaRegistry, ActiveSessions, PullRequest, GitHubIssue } from '../types';
import DeliberationPanel from './DeliberationPanel';

interface Props {
  registry: QuotaRegistry;
  sessions: ActiveSessions;
  pullRequests: PullRequest[];
  issues: GitHubIssue[];
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

export default function DashboardPage({ registry, sessions, pullRequests }: Props) {
  const providers = registry.providers || {};
  const providerEntries = Object.entries(providers);

  const totalCostToday = providerEntries.reduce((sum, [, p]) => sum + (p.usage_today?.estimated_cost_usd || 0), 0);
  const totalCallsToday = providerEntries.reduce((sum, [, p]) => sum + (p.usage_today?.calls || 0), 0);
  const activeDelegations = sessions.active_delegations?.length || 0;
  const openPRs = pullRequests.filter(pr => pr.state === 'OPEN').length;
  const conflictingPRs = pullRequests.filter(pr => pr.mergeable === 'CONFLICTING').length;

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
          value={String(activeDelegations)}
          subtitle="aktive Delegierungen"
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
                  formatter={(value: number, _name: string, props: { payload: { limit: number } }) => [
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

      {/* Dual-CEO Deliberation Panel */}
      <DeliberationPanel deliberations={sessions.deliberation_log || []} />

      {/* Active Workstreams */}
      {activeDelegations > 0 && (
        <div className="glass-card p-6">
          <h3 className="text-lg font-semibold text-slate-200 mb-4">Aktive Workstreams</h3>
          <div className="space-y-4">
            {sessions.active_delegations.map((d) => {
              const issue = issues?.find(i => i.number.toString() === d.issue_number);
              let pr = null;
              if (d.pr_url) {
                pr = pullRequests?.find(p => p.url === d.pr_url);
              }
              if (!pr) {
                pr = pullRequests?.find(p => p.title.includes(`#${d.issue_number}`) || p.headRefName.includes(d.issue_number));
              }
              
              const hasFailingChecks = pr?.statusCheckRollup?.some((c: any) => c.conclusion === 'FAILURE' || c.status === 'FAILURE');
              
              return (
                <div key={d.jules_session_id} className="bg-slate-900/40 border border-slate-700/30 rounded-xl p-4 flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                  {/* Issue Info */}
                  <div className="flex-1 border-b md:border-b-0 md:border-r border-slate-700/50 pb-4 md:pb-0 md:pr-4">
                    <div className="flex items-center gap-2 mb-2">
                      <AlertCircle className="w-4 h-4 text-slate-400" />
                      <span className="text-xs text-purple-400 font-mono">#{d.issue_number}</span>
                    </div>
                    <span className="text-sm font-medium text-slate-200 line-clamp-2" title={d.issue_title}>{d.issue_title}</span>
                  </div>
                  
                  {/* Jules Session Info */}
                  <div className="flex-1 flex flex-col items-start md:items-center border-b md:border-b-0 md:border-r border-slate-700/50 pb-4 md:pb-0 md:px-4">
                    <div className="flex items-center gap-2 mb-2">
                      <Activity className="w-4 h-4 text-purple-400" />
                      <span className="text-sm font-medium text-slate-300">Jules Session</span>
                    </div>
                    <div className="flex flex-col items-start md:items-center gap-1.5">
                       <JulesStateBadge state={d.jules_state} />
                       <span className="text-[10px] text-slate-500">Retries: {d.retry_count} • {timeAgo(d.last_checked_at)}</span>
                    </div>
                  </div>

                  {/* PR Info */}
                  <div className="flex-1 flex flex-col items-start md:items-end md:pl-4">
                    <div className="flex items-center gap-2 mb-2">
                      <GitPullRequest className="w-4 h-4 text-cyan-400" />
                      <span className="text-sm font-medium text-slate-300">Pull Request</span>
                    </div>
                    {pr ? (
                      <div className="flex flex-col items-start md:items-end gap-1.5">
                        <a href={pr.url} target="_blank" rel="noopener noreferrer" className="text-xs text-cyan-400 hover:text-cyan-300 font-mono mb-1">
                          #{pr.number} {pr.headRefName}
                        </a>
                        {hasFailingChecks ? (
                          <span className="badge bg-red-500/20 text-red-400 flex items-center gap-1"><AlertCircle className="w-3 h-3"/> Checks Failed</span>
                        ) : pr.mergeable === 'CONFLICTING' ? (
                          <span className="badge bg-orange-500/20 text-orange-400">Merge Conflict</span>
                        ) : pr.mergeable === 'MERGEABLE' ? (
                          <span className="badge bg-emerald-500/20 text-emerald-400 flex items-center gap-1"><CheckCircle className="w-3 h-3"/> Mergeable</span>
                        ) : (
                          <span className="badge bg-slate-500/20 text-slate-400">{pr.state}</span>
                        )}
                      </div>
                    ) : (
                      <span className="text-xs text-slate-500 italic mt-1">Noch kein PR</span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
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
