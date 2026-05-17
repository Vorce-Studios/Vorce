import { useCallback, useEffect, useState } from 'react';
import { XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, AreaChart, Area } from 'recharts';
import { Activity, BrainCircuit, Cpu, RefreshCw, Layers, Clock, Link as LinkIcon, BarChart3, ChevronDown, ChevronRight } from 'lucide-react';

interface QuotaData {
  date: string;
  provider_name: string;
  model_name: string;
  calls: number;
  cost_usd: number;
  input_tokens: number;
  output_tokens: number;
  cached_tokens: number;
  reasoning_tokens: number;
  tool_tokens: number;
  total_duration_ms: number;
}

interface RegistryData {
  last_reset_date?: string;
  providers: {
    [key: string]: {
      enabled: boolean;
      daily_budget_usd: number;
      daily_limit: number;
      purpose: string[];
      models?: { [key: string]: { name: string, estimated_cost_per_call_usd: number } };
      usage_today?: { [key: string]: any };
    }
  }
}

// Unified Task Item
type TaskStatus =
  | 'JULES_RUNNING'
  | 'JULES_PLANNING'
  | 'JULES_QUEUED'
  | 'JULES_WAITING'
  | 'JULES_FAILED'
  | 'PR_REVIEW'
  | 'PR_CHECK_FAILED'
  | 'MERGE_CONFLICT'
  | 'GITHUB_OPEN'
  | 'COMPLETED'
  | 'ERROR';

interface TaskItem {
  id: string;
  title: string;
  status: TaskStatus;
  gh_status: string;
  priority: 'low' | 'medium' | 'high' | 'urgent';
  task_type: string;
  sub_issues: { total: number, completed: number };
  jules_session_id?: string;
  timestamp?: string;
  raw?: any;
}

function StatCard({ title, value, icon: Icon, subtitle, highlightClass = "text-white", tooltip }: any) {
  return (
    <div className="glass-card p-6 flex flex-col relative overflow-hidden group" title={tooltip}>
      <div className="absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity">
        <Icon size={64} />
      </div>
      <div className="flex items-center gap-3 text-muted mb-2">
        <Icon size={20} className="text-primary" />
        <h3 className="font-medium text-sm">{title}</h3>
      </div>
      <div className={`text-3xl font-bold mb-1 ${highlightClass}`}>{value}</div>
      {subtitle && <div className="text-xs text-muted">{subtitle}</div>}
    </div>
  );
}

function ProgressBar({ current, max, colorClass }: { current: number, max: number, colorClass: string }) {
  const pct = max > 0 ? Math.min((current / max) * 100, 100) : 0;
  return (
    <div className="w-full bg-surface rounded-full h-1.5 mt-2 overflow-hidden border border-white/5 relative">
      <div className={`absolute top-0 left-0 bottom-0 ${colorClass}`} style={{ width: `${pct}%` }} />
    </div>
  );
}

function formatTokens(val: number): string {
  if (val >= 1_000_000) return `${(val / 1_000_000).toFixed(2)}M`;
  if (val >= 1000) return `${(val / 1000).toFixed(1)}k`;
  return val.toString();
}

function getRowTotalTokens(row: QuotaData): number {
  return row.input_tokens + row.output_tokens;
}

function getJulesScopedUsage(registry: RegistryData | null): any {
  return registry?.providers?.jules?.usage_today || {};
}

function formatQuotaWindow(minutes: unknown): string {
  const value = asNumber(minutes);
  if (value === 300) return '5h';
  if (value === 10080) return 'Weekly';
  if (value >= 1440) return `${Math.round(value / 1440)}d`;
  if (value >= 60) return `${Math.round(value / 60)}h`;
  return value > 0 ? `${value}m` : 'Quota';
}

function formatResetTime(value: unknown): string {
  const seconds = asNumber(value);
  if (seconds <= 0) return 'n/a';
  return new Date(seconds * 1000).toLocaleTimeString();
}

function formatDuration(secondsValue: unknown): string {
  const seconds = Math.max(0, Math.round(asNumber(secondsValue)));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

function formatDateTime(value: unknown): string {
  if (!value) return 'n/a';
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return 'n/a';
  return date.toLocaleTimeString();
}

function ProviderCard({ name, providerReg, modelsData }: { name: string, providerReg: any, modelsData: QuotaData[] }) {
  const limit = providerReg?.daily_limit || 0;
  const usage = providerReg?.usage_today || {};
  const rateLimits = usage.rate_limits;
  const julesQuotaObserved = asNumber(usage.account_sessions_observed_rolling_24h || usage.calls);

  const totalCalls = modelsData.reduce((acc, curr) => acc + curr.calls, 0);
  const totalInput = modelsData.reduce((acc, curr) => acc + curr.input_tokens, 0);
  const totalOutput = modelsData.reduce((acc, curr) => acc + curr.output_tokens, 0);
  const totalCached = modelsData.reduce((acc, curr) => acc + curr.cached_tokens, 0);
  const totalTokens = totalInput + totalOutput;
  const cachePct = totalInput > 0 ? (totalCached / totalInput) * 100 : 0;
  const callPct = limit > 0 ? (totalCalls / limit) * 100 : 0;
  const primaryQuotaPct = rateLimits?.primary ? asNumber(rateLimits.primary.used_percent) : callPct;
  const secondaryQuotaPct = rateLimits?.secondary ? asNumber(rateLimits.secondary.used_percent) : null;
  const primaryLabel = rateLimits?.primary ? (rateLimits.primary.label || `${formatQuotaWindow(rateLimits.primary.window_minutes)} limit`) : 'Daily quota';
  const secondaryLabel = rateLimits?.secondary ? (rateLimits.secondary.label || `${formatQuotaWindow(rateLimits.secondary.window_minutes)} limit`) : 'Fallback signal';
  const isJules = name === 'jules';

  return (
    <div className="glass-card p-6 border border-white/5 animate-fade-in">
      <div className="flex justify-between items-start mb-4">
        <div>
          <h3 className="text-xl font-bold text-white capitalize flex items-center gap-2">
            {name.replace('_', ' ')}
            {totalCalls === 0 && <span className="text-[10px] bg-white/5 text-muted px-2 py-0.5 rounded-full border border-white/10">Idle</span>}
          </h3>
          {providerReg?.purpose && (
            <div className="flex gap-2 mt-2 flex-wrap">
              {providerReg.purpose.map((p: string) => (
                <span key={p} className="text-xs uppercase tracking-wider bg-white/5 text-muted px-2 py-1 rounded border border-white/10">{p}</span>
              ))}
            </div>
          )}
        </div>
        <div className="px-4 py-2 rounded-full bg-primary/20 text-primary text-sm font-bold border border-primary/30">
          {isJules ? `${julesQuotaObserved} observed / ${limit}` : `${totalCalls} / ${limit} calls`}
        </div>
      </div>

      <div className="mb-6 bg-surface/50 p-4 rounded-xl border border-white/5">
        <div className="flex justify-between items-end mb-2">
          <span className="text-muted text-sm font-medium">{isJules ? 'Session Throughput' : 'Token Load Today'}</span>
          <span className="text-lg font-bold text-accent">
            {isJules ? `${julesQuotaObserved} sessions` : formatTokens(totalTokens)}
          </span>
        </div>
        <ProgressBar current={isJules ? julesQuotaObserved : primaryQuotaPct} max={isJules ? limit : 100} colorClass="bg-accent" />
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mb-6 text-xs">
        <div className="bg-background rounded-lg p-3 border border-white/5">
          <div className="text-muted mb-1">Source</div>
          <div className="text-white font-medium truncate" title={usage.source}>{usage.source || 'registry'}</div>
        </div>
        <div className="bg-background rounded-lg p-3 border border-white/5">
          <div className="text-muted mb-1">Last Sync</div>
          <div className="text-white font-medium">{usage.last_synced_at ? new Date(usage.last_synced_at).toLocaleTimeString() : 'n/a'}</div>
        </div>
        <div className="bg-background rounded-lg p-3 border border-white/5">
          <div className="text-muted mb-1">{isJules ? 'API Observed 24h' : primaryLabel}</div>
          <div className="text-white font-medium">{isJules ? `${julesQuotaObserved}/${limit}` : `${primaryQuotaPct.toFixed(1)}%`}</div>
          {!isJules && (
            <div className="text-[10px] text-muted mt-1">
              {rateLimits?.primary ? `Reset ${formatResetTime(rateLimits.primary.resets_at)}` : `${totalCalls}/${limit} calls`}
            </div>
          )}
        </div>
        <div className="bg-background rounded-lg p-3 border border-white/5">
          <div className="text-muted mb-1">{isJules ? 'Vorce Live/Waiting' : secondaryLabel}</div>
          <div className="text-white font-medium">
            {isJules
              ? `${asNumber(usage.active_sessions)}/${asNumber(usage.pending_sessions)}`
              : secondaryQuotaPct !== null ? `${secondaryQuotaPct.toFixed(1)}%` : `${cachePct.toFixed(1)}% cache`}
          </div>
          {!isJules && rateLimits?.secondary && (
            <div className="text-[10px] text-muted mt-1">Reset {formatResetTime(rateLimits.secondary.resets_at)}</div>
          )}
          {isJules && (
            <div className="text-[10px] text-muted mt-1">calendar day: {asNumber(usage.account_sessions_observed_today)}</div>
          )}
        </div>
      </div>

      {!isJules && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-6">
          <div className="bg-background rounded-lg p-3 border border-white/5">
            <div className="flex justify-between text-xs mb-2">
              <span className="text-muted">{primaryLabel} used</span>
              <span className="text-white font-medium">{primaryQuotaPct.toFixed(1)}%</span>
            </div>
            <ProgressBar current={primaryQuotaPct} max={100} colorClass="bg-primary" />
          </div>
          <div className="bg-background rounded-lg p-3 border border-white/5">
            <div className="flex justify-between text-xs mb-2">
              <span className="text-muted">{secondaryQuotaPct !== null ? `${secondaryLabel} used` : 'Cache reuse'}</span>
              <span className="text-white font-medium">{secondaryQuotaPct !== null ? `${secondaryQuotaPct.toFixed(1)}%` : `${cachePct.toFixed(1)}%`}</span>
            </div>
            <ProgressBar current={secondaryQuotaPct !== null ? secondaryQuotaPct : cachePct} max={100} colorClass="bg-secondary" />
          </div>
        </div>
      )}

      <div className="space-y-3">
        <div className="text-sm font-bold text-white/70 uppercase tracking-wider border-b border-white/10 pb-2 mb-3">Model Breakdown</div>

        {modelsData.length === 0 && (
          <div className="text-sm text-muted italic text-center py-6 bg-surface/20 rounded-xl border border-dashed border-white/10">
            No active usage recorded for {name} today.
          </div>
        )}

        {modelsData.map((mdl, idx) => (
          <div key={idx} className="bg-background rounded-xl p-4 border border-white/5 hover:border-white/10 transition-colors">
            <div className="flex justify-between items-center font-bold text-white mb-3">
              <span className="text-base">{mdl.model_name}</span>
              <span className="text-accent bg-accent/10 px-2 py-1 rounded text-sm">{mdl.calls} calls</span>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3 text-xs">
              <div className="flex flex-col bg-surface/30 p-2 rounded"><span className="text-muted mb-1">Total</span><span className="font-medium text-white">{formatTokens(getRowTotalTokens(mdl))}</span></div>
              <div className="flex flex-col bg-surface/30 p-2 rounded"><span className="text-muted mb-1">In/Out</span><span className="font-medium text-white">{formatTokens(mdl.input_tokens)}/{formatTokens(mdl.output_tokens)}</span></div>
              <div className="flex flex-col bg-surface/30 p-2 rounded"><span className="text-muted mb-1">Cached</span><span className="font-medium text-secondary">{formatTokens(mdl.cached_tokens)}</span></div>
              <div className="flex flex-col bg-surface/30 p-2 rounded"><span className="text-muted mb-1">Reasoning</span><span className="font-medium text-primary">{formatTokens(mdl.reasoning_tokens)}</span></div>
              <div className="flex flex-col bg-surface/30 p-2 rounded"><span className="text-muted mb-1">Tools</span><span className="font-medium text-green-400">{formatTokens(mdl.tool_tokens)}</span></div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// Random colors for dynamic area charts
const COLORS = ['#6366f1', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4'];
const USAGE_META_KEYS = new Set([
  'calls',
  'estimated_cost_usd',
  'source',
  'last_synced_at',
  'rate_limits',
  'quota_buckets',
  'quota_source',
  'quota_synced_at',
  'quota_error',
  'active_sessions',
  'completed_sessions',
  'failed_sessions',
  'pending_sessions',
  'api_sessions_seen',
  'last_error',
  'api_sessions_today'
]);

function asNumber(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function mergeQuotaRows(baseRows: QuotaData[], liveRows: QuotaData[]): QuotaData[] {
  const rows = new Map<string, QuotaData>();
  baseRows.forEach(row => rows.set(`${row.date}|${row.provider_name}|${row.model_name}`, row));
  liveRows.forEach(row => rows.set(`${row.date}|${row.provider_name}|${row.model_name}`, row));
  return Array.from(rows.values());
}

function getLiveQuotaRows(registry: RegistryData | null, today: string): QuotaData[] {
  if (!registry?.providers || registry.last_reset_date !== today) return [];

  const rows: QuotaData[] = [];
  Object.entries(registry.providers).forEach(([providerName, provider]) => {
    const usage = provider.usage_today;
    if (!usage) return;

    Object.entries(usage).forEach(([modelName, modelUsage]) => {
      if (USAGE_META_KEYS.has(modelName) || !modelUsage || typeof modelUsage !== 'object' || !('calls' in modelUsage)) {
        return;
      }

      rows.push({
        date: today,
        provider_name: providerName,
        model_name: modelName,
        calls: asNumber(modelUsage.calls),
        cost_usd: asNumber(modelUsage.estimated_cost_usd),
        input_tokens: asNumber(modelUsage.total_input_tokens),
        output_tokens: asNumber(modelUsage.total_output_tokens),
        cached_tokens: asNumber(modelUsage.cached_tokens),
        reasoning_tokens: asNumber(modelUsage.reasoning_tokens),
        tool_tokens: asNumber(modelUsage.tool_tokens),
        total_duration_ms: asNumber(modelUsage.total_duration_ms)
      });
    });

    if (!rows.some(row => row.provider_name === providerName) && asNumber(usage.calls) > 0) {
      rows.push({
        date: today,
        provider_name: providerName,
        model_name: 'aggregate',
        calls: asNumber(usage.calls),
        cost_usd: asNumber(usage.estimated_cost_usd),
        input_tokens: 0,
        output_tokens: 0,
        cached_tokens: 0,
        reasoning_tokens: 0,
        tool_tokens: 0,
        total_duration_ms: 0
      });
    }
  });

  return rows;
}

export default function App() {
  const [historicalData, setHistoricalData] = useState<QuotaData[]>([]);
  const [activeSessions, setActiveSessions] = useState<any | null>(null);
  const [registry, setRegistry] = useState<RegistryData | null>(null);
  const [ghIssues, setGhIssues] = useState<any[]>([]);
  const [pullRequests, setPullRequests] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const [activeTab, setActiveTab] = useState<string>('');
  const [chartMetric, setChartMetric] = useState<'total_tokens'|'tokens_in'|'tokens_out'|'reasoning'|'calls'>('total_tokens');
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterPriority, setFilterPriority] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [expandedIssueIds, setExpandedIssueIds] = useState<Set<string>>(new Set());

  const fetchData = useCallback(async () => {
    try {
      const ts = new Date().getTime();
      const [dataRes, sessionsRes, registryRes, ghIssuesRes, pullRequestsRes] = await Promise.all([
        fetch(`/data.json?t=${ts}`).catch(() => null),
        fetch(`/active-sessions.json?t=${ts}`).catch(() => null),
        fetch(`/registry.json?t=${ts}`).catch(() => null),
        fetch(`/github-issues.json?t=${ts}`).catch(() => null),
        fetch(`/pull-requests.json?t=${ts}`).catch(() => null)
      ]);

      if (dataRes?.ok) setHistoricalData(await dataRes.json());
      if (sessionsRes?.ok) setActiveSessions(await sessionsRes.json());
      if (ghIssuesRes?.ok) setGhIssues(await ghIssuesRes.json());
      if (pullRequestsRes?.ok) setPullRequests(await pullRequestsRes.json());

      if (registryRes?.ok) {
        const reg = await registryRes.json();
        setRegistry(reg);
        // Set default tab if not set
        if (!activeTab && reg.providers) {
          const firstProvider = Object.keys(reg.providers).find(k => reg.providers[k].enabled);
          if (firstProvider) setActiveTab(firstProvider);
        }
      }
    } catch (e) {
      console.error("Error fetching data", e);
    } finally {
      setLoading(false);
    }
  }, [activeTab]);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 60000);
    return () => clearInterval(interval);
  }, [fetchData]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-4">
          <RefreshCw className="animate-spin text-primary" size={32} />
          <p className="text-muted animate-pulse">Initializing Vorce Autopilot Analytics...</p>
        </div>
      </div>
    );
  }

  const today = new Date().toISOString().split('T')[0];
  const liveQuotaRows = getLiveQuotaRows(registry, today);
  const chartSourceData = mergeQuotaRows(historicalData, liveQuotaRows);
  const todayData = mergeQuotaRows(historicalData.filter(d => d.date === today), liveQuotaRows);

  const totalInputTokens = todayData.reduce((acc, curr) => acc + curr.input_tokens, 0);
  const totalOutputTokens = todayData.reduce((acc, curr) => acc + curr.output_tokens, 0);
  const totalCachedTokens = todayData.reduce((acc, curr) => acc + curr.cached_tokens, 0);
  const totalReasoning = todayData.reduce((acc, curr) => acc + (curr.reasoning_tokens || 0), 0);
  const totalProviderCalls = todayData.reduce((acc, curr) => acc + curr.calls, 0);
  const totalTokens = totalInputTokens + totalOutputTokens;
  const cacheReusePct = totalInputTokens > 0 ? (totalCachedTokens / totalInputTokens) * 100 : 0;

  const providersList = registry?.providers ? Object.entries(registry.providers).filter(([_, p]) => p.enabled) : [];

  // --- Issue Board Processing ---
  const issueTasks: TaskItem[] = [];

  const parseIssueMetadata = (issue: any) => {
    const labels = issue.labels?.map((l: any) => typeof l === 'string' ? l : l.name) || [];
    const normalizedLabels = labels.map((label: string) => label.toLowerCase());
    const priority =
      normalizedLabels.find((label: string) => ['low', 'medium', 'high', 'urgent'].includes(label)) ||
      normalizedLabels.find((label: string) => /^priority:\s*(low|medium|high|critical)$/.test(label)) ||
      'medium';
    const title = String(issue.title || issue.issue_title || issue.topic || '');

    const body = issue.body || '';
    const taskMatches = body.match(/-\s*\[([ xX])\]/g) || [];
    const completed = taskMatches.filter((m: string) => m.toLowerCase().includes('x')).length;

    // Naming convention parsing
    let typeIcon = 'Issue';
    if (title.includes('MF-StMa_') || /\[MASTER\]$/.test(title)) typeIcon = 'Master';
    if (title.includes('MF-StIs_') || /\[ISSUE\]$/.test(title)) typeIcon = 'Issue';
    if (title.includes('MF-User_')) typeIcon = 'User';
    if (title.includes('__MF-SubI_') || /\[M\d+-S\d{2}\]$/.test(title)) typeIcon = 'Sub';

    const normalizedPriority = priority.startsWith('priority:')
      ? priority.replace(/^priority:\s*/, '')
      : priority;

    return {
      priority: (normalizedPriority === 'critical' ? 'urgent' : normalizedPriority) as any,
      taskType: typeIcon,
      subIssues: { total: taskMatches.length, completed }
    };
  };

  const getParentIssueNumber = (issue: any): number | null => {
    const body = String(issue.body || '');
    const match = body.match(/(?:Part of|Parent issue:)\s+(?:[\w-]+\/[\w-]+)?#(\d+)/i);
    return match ? Number(match[1]) : null;
  };

  const getIssueRemoteState = (issue: any): string => {
    const body = String(issue.body || '');
    const match = body.match(/<!--\s*vorce-remote-state:\s*([a-z-]+)\s*-->/i);
    return match ? match[1].toUpperCase().replace(/-/g, '_') : '';
  };

  const getUnifiedStatus = (task: any, source: 'JULES' | 'GITHUB' | 'REVIEW'): TaskStatus => {
    if (task.github_state === 'CLOSED' || task.state === 'CLOSED') return 'COMPLETED';

    if (source === 'JULES' || task.jules_session_id) {
      const state = String(task.jules_state || task.status || '').toUpperCase();
      if (/FAILED|ERROR|CANCEL/.test(state)) return 'JULES_FAILED';
      if (/AWAITING|PENDING|PAUSED|FEEDBACK|APPROVAL/.test(state)) return 'JULES_WAITING';
      if (/PLANNING|PLAN/.test(state)) return 'JULES_PLANNING';
      if (/QUEUED/.test(state)) return 'JULES_QUEUED';
      if (/IN_PROGRESS|RUNNING|ACTIVE|WORKING/.test(state)) return 'JULES_RUNNING';
      if (/COMPLETE|DONE/.test(state)) return task.pr_url ? 'PR_REVIEW' : 'COMPLETED';
    }

    if (source === 'REVIEW' || task.pr_url) {
      return 'PR_REVIEW';
    }

    return 'GITHUB_OPEN';
  };

  const getPrChecks = (pr: any) => {
    const checks = Array.isArray(pr.statusCheckRollup) ? pr.statusCheckRollup : [];
    const failing = checks.filter((check: any) => {
      const conclusion = String(check.conclusion || '').toUpperCase();
      const status = String(check.status || '').toUpperCase();
      const state = String(check.state || '').toUpperCase();
      return ['FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED'].includes(conclusion) ||
        status === 'FAILURE' ||
        status === 'ERROR' ||
        state === 'FAILURE' ||
        state === 'ERROR';
    });
    const pending = checks.filter((check: any) => {
      const conclusion = String(check.conclusion || '').toUpperCase();
      const status = String(check.status || '').toUpperCase();
      const state = String(check.state || '').toUpperCase();
      return (!conclusion && status && status !== 'COMPLETED' && status !== 'SUCCESS') || state === 'PENDING';
    });
    return { failing, pending };
  };

  const openIssueNumbers = new Set(
    ghIssues
      .filter((issue: any) => String(issue.state || '').toUpperCase() === 'OPEN')
      .map((issue: any) => Number(issue.number))
  );
  const parentNumbersWithOpenChildren = new Set(
    ghIssues
      .filter((issue: any) => String(issue.state || '').toUpperCase() === 'OPEN')
      .map((issue: any) => getParentIssueNumber(issue))
      .filter((issueNumber: number | null): issueNumber is number => Number(issueNumber) > 0)
  );

  ghIssues
    .filter((issue: any) =>
      openIssueNumbers.has(Number(issue.number)) ||
      parentNumbersWithOpenChildren.has(Number(issue.number))
    )
    .forEach((issue: any) => {
    const issueIdStr = issue.number.toString();
    const meta = parseIssueMetadata(issue);
    const delegation = activeSessions?.active_delegations?.find((d: any) => Number(d.issue_number) === Number(issue.number));
    const review = activeSessions?.review_queue?.find((d: any) => Number(d.issue_number) === Number(issue.number));
    const bodyRemoteState = getIssueRemoteState(issue);
    const status = delegation
      ? getUnifiedStatus(delegation, 'JULES')
      : review
        ? getUnifiedStatus(review, 'REVIEW')
        : bodyRemoteState
          ? getUnifiedStatus({ ...issue, jules_state: bodyRemoteState, jules_session_id: 'from-issue-body' }, 'JULES')
          : getUnifiedStatus(issue, 'GITHUB');

    issueTasks.push({
      id: issueIdStr,
      title: issue.title,
      status,
      gh_status: issue.state,
      priority: meta.priority,
      task_type: meta.taskType,
      sub_issues: meta.subIssues,
      jules_session_id: delegation?.jules_session_id,
      timestamp: delegation?.last_checked_at || issue.updatedAt,
      raw: {
        ...issue,
        parent_issue_number: getParentIssueNumber(issue),
        body_remote_state: bodyRemoteState,
        delegation,
        review
      }
    });
  });

  const filteredIssues = issueTasks.filter(task => {
    const matchesStatus = filterStatus === 'all' || task.status === filterStatus;
    const matchesPriority = filterPriority === 'all' || task.priority === filterPriority;
    const matchesSearch = task.title.toLowerCase().includes(searchQuery.toLowerCase()) || task.id.includes(searchQuery);
    return matchesStatus && matchesPriority && matchesSearch;
  });

  const statusWeight: Record<TaskStatus, number> = {
    ERROR: 10,
    JULES_FAILED: 9,
    PR_CHECK_FAILED: 8,
    MERGE_CONFLICT: 8,
    JULES_WAITING: 7,
    JULES_RUNNING: 6,
    JULES_PLANNING: 5,
    PR_REVIEW: 4,
    JULES_QUEUED: 3,
    GITHUB_OPEN: 2,
    COMPLETED: 1
  };
  filteredIssues.sort((a, b) => statusWeight[b.status] - statusWeight[a.status] || Number(b.id) - Number(a.id));
  const subIssuesByParent = new Map<number, TaskItem[]>();
  filteredIssues.forEach(issue => {
    const parentNumber = Number(issue.raw?.parent_issue_number || 0);
    if (parentNumber > 0) {
      const items = subIssuesByParent.get(parentNumber) || [];
      items.push(issue);
      subIssuesByParent.set(parentNumber, items);
    }
  });
  const visibleRootIssues = filteredIssues.filter(issue => !issue.raw?.parent_issue_number || !filteredIssues.some(candidate => Number(candidate.id) === Number(issue.raw.parent_issue_number)));
  const activeIssueStatuses: TaskStatus[] = ['JULES_RUNNING', 'JULES_PLANNING', 'JULES_QUEUED', 'JULES_WAITING', 'JULES_FAILED', 'PR_REVIEW'];
  const openIssueCount = issueTasks.filter(issue => issue.gh_status === 'OPEN').length;
  const activeIssueCount = issueTasks.filter(issue => issue.gh_status === 'OPEN' && activeIssueStatuses.includes(issue.status)).length;
  const inactiveIssueCount = openIssueCount - activeIssueCount;
  const masterIssueCount = issueTasks.filter(issue => issue.gh_status === 'OPEN' && issue.task_type === 'Master').length;
  const subIssueCount = issueTasks.filter(issue => issue.gh_status === 'OPEN' && issue.task_type === 'Sub').length;

  const julesUsage = getJulesScopedUsage(registry);
  const scopedActiveJules = asNumber(julesUsage.scoped_live_capacity_sessions ?? julesUsage.active_sessions);
  const scopedWaitingJules = asNumber(julesUsage.scoped_live_waiting_sessions ?? julesUsage.pending_sessions);
  const openPullRequests = pullRequests.filter(pr => String(pr.state || 'OPEN').toUpperCase() === 'OPEN');
  const reviewQueue = activeSessions?.review_queue || [];
  const activePrActions = activeSessions?.active_pr_actions || [];
  const prChecksRun = openPullRequests.filter(pr => getPrChecks(pr).pending.length > 0).length;
  const prCheckFails = openPullRequests.filter(pr => getPrChecks(pr).failing.length > 0).length;
  const prMergeConflicts = openPullRequests.filter(pr => pr.mergeable === 'CONFLICTING').length;
  const prReviewRun = reviewQueue.filter((review: any) => review.review_status === 'running').length;
  const prReviewNeeded = openPullRequests.filter(pr => {
    const { failing, pending } = getPrChecks(pr);
    const hasReview = reviewQueue.some((review: any) => Number(review.pr_number) === Number(pr.number));
    return pr.mergeable === 'MERGEABLE' && failing.length === 0 && pending.length === 0 && !hasReview;
  }).length;
  const prReworkNeeded = activePrActions.filter((action: any) =>
    (action.action_type === 'check_fix_comment' && action.status === 'COMMENTED') ||
    (action.action_type === 'merge_conflict_cli' && ['FAILED', 'BLOCKED'].includes(String(action.status)))
  ).length;
  const scheduler = activeSessions?.scheduler || {};

  // --- Advanced Chart Processing ---
  const chartMap = new Map<string, any>();
  const modelsInChart = new Set<string>();

  chartSourceData.forEach(curr => {
    if (!chartMap.has(curr.date)) {
      chartMap.set(curr.date, { date: curr.date });
    }
    const dayData = chartMap.get(curr.date);
    const key = `${curr.provider_name}: ${curr.model_name}`;
    modelsInChart.add(key);

    let val = 0;
    if (chartMetric === 'total_tokens') val = getRowTotalTokens(curr);
    if (chartMetric === 'tokens_in') val = curr.input_tokens;
    if (chartMetric === 'tokens_out') val = curr.output_tokens;
    if (chartMetric === 'reasoning') val = curr.reasoning_tokens || 0;
    if (chartMetric === 'calls') val = curr.calls;

    dayData[key] = (dayData[key] || 0) + val;
  });

  const chartData = Array.from(chartMap.values()).sort((a: any, b: any) => a.date.localeCompare(b.date)).slice(-14);
  const modelsArray = Array.from(modelsInChart);

  const getStatusColor = (status: string) => {
    switch(status) {
      case 'JULES_RUNNING': return 'bg-green-500/20 text-green-400 border-green-500/30';
      case 'JULES_PLANNING': return 'bg-cyan-500/20 text-cyan-300 border-cyan-500/30';
      case 'JULES_QUEUED': return 'bg-slate-500/20 text-slate-300 border-slate-500/30';
      case 'JULES_WAITING': return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
      case 'JULES_FAILED': return 'bg-red-500/20 text-red-400 border-red-500/30';
      case 'PR_CHECK_FAILED': return 'bg-red-500/20 text-red-300 border-red-500/30';
      case 'MERGE_CONFLICT': return 'bg-orange-500/20 text-orange-300 border-orange-500/30';
      case 'PR_REVIEW': return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
      case 'GITHUB_OPEN': return 'bg-gray-500/20 text-gray-400 border-gray-500/30';
      case 'ERROR': return 'bg-red-500/20 text-red-400 border-red-500/30';
      case 'COMPLETED': return 'bg-purple-500/20 text-purple-400 border-purple-500/30';
      default: return 'bg-surface text-white border-white/10';
    }
  };

  const getStatusLabel = (task: TaskItem) => {
    const raw = task.raw || {};
    switch(task.status) {
      case 'JULES_RUNNING': return 'Jules: Working';
      case 'JULES_PLANNING': return 'Jules: Planning';
      case 'JULES_QUEUED': return 'Jules: Queued';
      case 'JULES_WAITING': return 'Jules: Waiting';
      case 'JULES_FAILED': return 'Jules: Failed';
      case 'ERROR': return `Error: ${raw.message || 'Unknown'}`;
      case 'PR_CHECK_FAILED': return `PR: ${raw.failing_checks?.length || 0} Checks Failed`;
      case 'MERGE_CONFLICT': return 'PR: Merge Conflict';
      case 'PR_REVIEW': {
        return 'Review: Pending';
      }
      case 'GITHUB_OPEN': return 'GitHub: Open';
      case 'COMPLETED': return 'GitHub: Completed / Closed';
      default: return task.status;
    }
  };

  const toggleIssueExpansion = (issueId: string) => {
    setExpandedIssueIds(prev => {
      const next = new Set(prev);
      if (next.has(issueId)) next.delete(issueId);
      else next.add(issueId);
      return next;
    });
  };

  const renderIssueRow = (task: TaskItem, isChild = false) => {
    const childIssues = subIssuesByParent.get(Number(task.id)) || [];
    const isExpanded = expandedIssueIds.has(task.id);
    return (
      <div key={task.id} className={isChild ? 'ml-8 border-l border-white/10 pl-4' : ''}>
        <div className="bg-surface/30 rounded-xl p-4 border border-white/5 flex flex-col md:flex-row md:items-center justify-between gap-4 hover:bg-surface/50 transition-colors">
          <div className="flex items-center gap-4 flex-1 overflow-hidden">
            <div className="w-6 shrink-0">
              {childIssues.length > 0 && (
                <button
                  type="button"
                  onClick={() => toggleIssueExpansion(task.id)}
                  className="text-muted hover:text-white transition-colors"
                  title={isExpanded ? 'Sub-Issues einklappen' : 'Sub-Issues ausklappen'}
                >
                  {isExpanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
                </button>
              )}
            </div>
            <div className={`px-3 py-1 rounded border text-xs font-bold whitespace-nowrap min-w-[150px] text-center ${getStatusColor(task.status)}`}>
              {getStatusLabel(task)}
            </div>
            <div className="flex flex-col overflow-hidden flex-1">
              <div className="flex items-center gap-2 mb-1">
                <span className="font-mono text-xs text-muted">#{task.id}</span>
                <a
                  href={task.raw?.url || `https://github.com/Vorce-Studios/Vorce/issues/${task.id}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-bold text-white truncate hover:text-primary transition-colors text-sm md:text-base"
                  title={task.title}
                >
                  {task.title}
                </a>
              </div>
              <div className="flex flex-wrap items-center gap-3">
                <span className={`text-[10px] uppercase font-black px-1.5 py-0.5 rounded ${
                  task.priority === 'urgent' ? 'bg-red-500 text-white' :
                  task.priority === 'high' ? 'bg-orange-500 text-white' :
                  task.priority === 'medium' ? 'bg-blue-500 text-white' : 'bg-gray-500 text-white'
                }`}>
                  {task.priority}
                </span>
                <span className="text-[10px] text-muted-foreground bg-white/5 px-1.5 py-0.5 rounded border border-white/5 italic">
                  {task.task_type}
                </span>
                {childIssues.length > 0 && (
                  <span className="text-[10px] text-primary flex items-center gap-1 font-bold">
                    <Layers size={10} /> Sub-Issues: {childIssues.length}
                  </span>
                )}
                {task.timestamp && (
                  <span className="text-[10px] text-muted flex items-center gap-1">
                    <Clock size={10} /> {new Date(task.timestamp).toLocaleTimeString()}
                  </span>
                )}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <div className="hidden lg:flex flex-col items-end mr-2">
              <span className="text-[10px] text-muted uppercase font-bold">State</span>
              <span className="text-xs font-mono text-white/70">{task.gh_status}</span>
            </div>
            {task.jules_session_id && (
              <a
                href={`https://jules.google.com/session/${task.jules_session_id}`}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary/10 hover:bg-primary/20 text-primary text-xs font-mono border border-primary/20 transition-colors whitespace-nowrap"
              >
                <LinkIcon size={12} /> JULES SESSION
              </a>
            )}
          </div>
        </div>
        {isExpanded && childIssues.length > 0 && (
          <div className="grid grid-cols-1 gap-3 mt-3">
            {childIssues.map(child => renderIssueRow(child, true))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="min-h-screen p-8 animate-fade-in bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-background via-[#0f0f16] to-[#050508]">
      <header className="mb-10 flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <h1 className="text-4xl font-black text-white mb-2 tracking-tight">
            Vorce <span className="text-gradient">Autopilot</span>
          </h1>
          <p className="text-muted flex items-center gap-2">
            <Activity size={16} className="text-primary animate-pulse-slow" />
            Live System Analytics & Telemetry
          </p>
        </div>
        <div className="flex flex-col items-end gap-2">
          <div className="glass px-4 py-2 rounded-full flex items-center gap-3">
            <div className={`w-2 h-2 rounded-full ${scopedActiveJules > 0 ? 'bg-green-500 animate-pulse' : 'bg-blue-500'}`} />
            <span className="text-sm font-medium text-white">{scopedActiveJules > 0 ? `${scopedActiveJules} Jules Active` : 'System Idle'}</span>
          </div>
          <div className="text-[10px] text-muted-foreground font-mono">Last Sync: {new Date().toLocaleTimeString()}</div>
        </div>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-6 gap-6 mb-10">
        <StatCard
          title="Token Load Today"
          value={formatTokens(totalTokens)}
          highlightClass="text-accent"
          icon={Cpu}
          tooltip="Gesamte Input- und Output-Tokens heute. Dieser Wert ist die Hauptbasis für spätere Modellumschaltung."
          subtitle={
            <div>
              <div className="flex justify-between mt-1 text-xs">
                <span className="text-primary">In: {formatTokens(totalInputTokens)}</span>
                <span className="text-secondary">Out: {formatTokens(totalOutputTokens)}</span>
              </div>
            </div>
          }
        />
        <StatCard
          title="Context Reuse"
          value={`${cacheReusePct.toFixed(1)}%`}
          icon={RefreshCw}
          tooltip="Anteil gecachter Input-Tokens. Hoher Cache-Anteil bedeutet niedrigere echte Kontextlast."
          subtitle={
            <div className="flex justify-between mt-1 text-xs">
              <span className="text-secondary">Cached: {formatTokens(totalCachedTokens)}</span>
              <span className="text-muted">Input: {formatTokens(totalInputTokens)}</span>
            </div>
          }
        />
        <StatCard
          title="Thinking Capacity"
          value={(totalReasoning / 1000).toFixed(1) + 'k'}
          icon={BrainCircuit}
          highlightClass="text-primary"
          tooltip="Anzahl der Tokens, die das Modell heute für internes 'Nachdenken' / Reasoning verwendet hat."
          subtitle="Tokens spent on internal reasoning"
        />
        <StatCard
          title="Provider Calls"
          value={totalProviderCalls}
          icon={Layers}
          tooltip="Summe der heute beobachteten Provider-Aufrufe aus den Telemetrie-Snapshots."
          subtitle="Codex, Gemini, Jules und weitere Provider"
        />
        <StatCard
          title="Next Monitor"
          value={formatDuration(scheduler.next_monitoring_in_seconds)}
          icon={Clock}
          highlightClass="text-yellow-300"
          tooltip="Zeit bis zum naechsten geplanten Monitoring-Run."
          subtitle={`at ${formatDateTime(scheduler.next_monitoring_at)}`}
        />
        <StatCard
          title="Next Planning"
          value={formatDuration(scheduler.next_planning_in_seconds)}
          icon={Clock}
          highlightClass="text-cyan-300"
          tooltip="Zeit bis zum naechsten geplanten Planning-Run."
          subtitle={`at ${formatDateTime(scheduler.next_planning_at)}`}
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-6 gap-6 mb-10">
        <StatCard
          title="Jules Active"
          value={scopedActiveJules}
          icon={Activity}
          highlightClass="text-green-300"
          tooltip="Aktive Jules-Sessions nur fuer die konfigurierte Vorce-Source."
          subtitle={`${scopedWaitingJules} need clarification`}
        />
        <StatCard
          title="Checks Run"
          value={prChecksRun}
          icon={RefreshCw}
          tooltip="Offene PRs mit mindestens einem noch laufenden Check."
          subtitle={`${openPullRequests.length} open PRs`}
        />
        <StatCard
          title="Check Fails"
          value={prCheckFails}
          icon={Activity}
          highlightClass="text-red-300"
          tooltip="Offene PRs mit mindestens einem fehlgeschlagenen Check."
          subtitle="needs fix"
        />
        <StatCard
          title="Merge Conflict"
          value={prMergeConflicts}
          icon={Layers}
          highlightClass="text-orange-300"
          tooltip="Offene PRs, die GitHub aktuell als CONFLICTING meldet."
          subtitle="CLI-first handling"
        />
        <StatCard
          title="Review Needed"
          value={prReviewNeeded}
          icon={BrainCircuit}
          tooltip="Offene, saubere und mergebare PRs ohne laufende oder bereits eingereihte Review."
          subtitle={`${prReviewRun} review running`}
        />
        <StatCard
          title="Rework Needed"
          value={prReworkNeeded}
          icon={Clock}
          highlightClass="text-yellow-300"
          tooltip="PRs, fuer die bereits Nacharbeit angefordert wurde oder deren Konfliktloesung blockiert ist."
          subtitle="follow-up required"
        />
      </div>

      {/* TABS & CHARTS SECTION */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-10">

        {/* Left: Provider Tabs */}
        <div className="glass-card flex flex-col overflow-hidden animate-slide-up">
          <div className="p-4 border-b border-white/10 flex items-center gap-2 overflow-x-auto custom-scrollbar">
            {providersList.map(([pName]) => (
              <button
                key={pName}
                onClick={() => setActiveTab(pName)}
                className={`px-4 py-2 rounded-lg text-sm font-semibold whitespace-nowrap transition-colors ${activeTab === pName ? 'bg-primary text-white' : 'bg-surface hover:bg-white/5 text-muted'}`}
              >
                {pName.replace('_', ' ')}
              </button>
            ))}
          </div>
          <div className="p-6 flex-1 bg-surface/10">
            {activeTab && registry?.providers[activeTab] && (
              <ProviderCard
                name={activeTab}
                providerReg={registry.providers[activeTab]}
                modelsData={todayData.filter(d => d.provider_name === activeTab)}
              />
            )}
          </div>
        </div>

        {/* Right: Advanced Historical Chart */}
        <div className="glass-card p-6 animate-slide-up flex flex-col" style={{ animationDelay: '100ms' }}>
          <div className="flex justify-between items-center mb-6">
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <BarChart3 size={20} className="text-secondary" />
              Historical Token Load
            </h2>
            <div className="flex gap-2">
              <select
                value={chartMetric}
                onChange={e => setChartMetric(e.target.value as any)}
                className="bg-surface border border-white/10 rounded-lg px-3 py-1 text-sm text-white focus:outline-none focus:border-primary"
              >
                <option value="total_tokens">Total Tokens</option>
                <option value="tokens_in">Input Tokens</option>
                <option value="tokens_out">Output Tokens</option>
                <option value="reasoning">Reasoning Tokens</option>
                <option value="calls">Calls / Sessions</option>
              </select>
            </div>
          </div>

          <div className="text-xs text-muted italic mb-4">
            {chartData.length <= 1 ? "Nur 1 Datenpunkt: Historie startet heute." : "Aufschlüsselung nach Modell über die letzten 14 Tage."}
          </div>

          <div className="flex-1 min-h-[300px] w-full">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#ffffff10" vertical={false} />
                <XAxis dataKey="date" stroke="#94a3b8" fontSize={12} tickMargin={10} />
                <YAxis stroke="#94a3b8" fontSize={12} tickFormatter={(val) => chartMetric === 'calls' ? `${val}` : formatTokens(Number(val))} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#151520', borderColor: '#2e2e3d', borderRadius: '12px' }}
                  itemStyle={{ color: '#f8fafc' }}
                  formatter={(value: any) => chartMetric === 'calls' ? Number(value).toLocaleString() : formatTokens(Number(value))}
                />
                {modelsArray.map((modelName, idx) => (
                  <Area
                    key={modelName}
                    type="monotone"
                    dataKey={modelName}
                    stackId="1"
                    stroke={COLORS[idx % COLORS.length]}
                    fill={COLORS[idx % COLORS.length]}
                    fillOpacity={0.6}
                  />
                ))}
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      {/* ISSUE BOARD */}
      {activeSessions && (
        <div className="glass-card p-6 animate-slide-up" style={{ animationDelay: '200ms' }}>
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-6 gap-4">
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <RefreshCw size={20} className="text-secondary" />
              Issue Overview
            </h2>

            <div className="flex flex-wrap gap-2 items-center">
              <input
                type="text"
                placeholder="Search issues..."
                value={searchQuery}
                onChange={e => setSearchQuery(e.target.value)}
                className="bg-surface border border-white/10 rounded-lg px-3 py-1.5 text-sm text-white focus:border-primary outline-none min-w-[200px]"
              />
              <select
                value={filterStatus}
                onChange={e => setFilterStatus(e.target.value)}
                className="bg-surface border border-white/10 rounded-lg px-3 py-1.5 text-sm text-white focus:border-primary outline-none"
              >
                <option value="all">All Status</option>
                <option value="JULES_RUNNING">Jules Running</option>
                <option value="JULES_PLANNING">Jules Planning</option>
                <option value="JULES_QUEUED">Jules Queued</option>
                <option value="JULES_WAITING">Jules Waiting</option>
                <option value="JULES_FAILED">Jules Failed</option>
                <option value="PR_CHECK_FAILED">PR Checks Failed</option>
                <option value="MERGE_CONFLICT">Merge Conflict</option>
                <option value="PR_REVIEW">PR Review</option>
                <option value="GITHUB_OPEN">GitHub Open</option>
                <option value="ERROR">System Error</option>
                <option value="COMPLETED">Completed</option>
              </select>
              <select
                value={filterPriority}
                onChange={e => setFilterPriority(e.target.value)}
                className="bg-surface border border-white/10 rounded-lg px-3 py-1.5 text-sm text-white focus:border-primary outline-none"
              >
                <option value="all">All Priority</option>
                <option value="urgent">Urgent</option>
                <option value="high">High</option>
                <option value="medium">Medium</option>
                <option value="low">Low</option>
              </select>
              <div className="text-xs bg-surface px-3 py-2 rounded text-muted border border-white/5">Matches: {filteredIssues.length}</div>
            </div>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6 text-sm">
            <div className="bg-background rounded-lg p-3 border border-white/5"><div className="text-muted text-xs">Open Issues</div><div className="text-white font-bold text-lg">{openIssueCount}</div></div>
            <div className="bg-background rounded-lg p-3 border border-white/5"><div className="text-muted text-xs">Active</div><div className="text-green-300 font-bold text-lg">{activeIssueCount}</div></div>
            <div className="bg-background rounded-lg p-3 border border-white/5"><div className="text-muted text-xs">Inactive</div><div className="text-white font-bold text-lg">{inactiveIssueCount}</div></div>
            <div className="bg-background rounded-lg p-3 border border-white/5"><div className="text-muted text-xs">Master</div><div className="text-cyan-300 font-bold text-lg">{masterIssueCount}</div></div>
            <div className="bg-background rounded-lg p-3 border border-white/5"><div className="text-muted text-xs">Sub-Issues</div><div className="text-primary font-bold text-lg">{subIssueCount}</div></div>
          </div>

          <div className="grid grid-cols-1 gap-3">
            {visibleRootIssues.length === 0 && (
              <div className="text-center py-10 text-muted border border-dashed border-white/10 rounded-xl">
                No issues matching your filters.
              </div>
            )}
            {visibleRootIssues.map(task => renderIssueRow(task))}
          </div>
        </div>
      )}
    </div>
  );
}
