import { useCallback, useEffect, useState } from 'react';
import { XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, AreaChart, Area } from 'recharts';
import { Activity, BrainCircuit, Cpu, DollarSign, RefreshCw, Layers, Clock, Link as LinkIcon, BarChart3 } from 'lucide-react';

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
interface TaskItem {
  id: string;
  title: string;
  status: 'IN_PROGRESS' | 'QUEUED' | 'PENDING_INPUT' | 'IN_REVIEW' | 'COMPLETED' | 'ERROR';
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

function ProviderCard({ name, providerReg, modelsData }: { name: string, providerReg: any, modelsData: QuotaData[] }) {
  const budget = providerReg?.daily_budget_usd || 0;
  const limit = providerReg?.daily_limit || 0;
  
  const totalCost = modelsData.reduce((acc, curr) => acc + curr.cost_usd, 0);
  const totalCalls = modelsData.reduce((acc, curr) => acc + curr.calls, 0);

  const formatTokens = (val: number) => val >= 1000 ? (val/1000).toFixed(1) + 'k' : val.toString();

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
          {totalCalls} / {limit} calls
        </div>
      </div>
      
      <div className="mb-6 bg-surface/50 p-4 rounded-xl border border-white/5">
        <div className="flex justify-between items-end mb-2">
          <span className="text-muted text-sm font-medium">Budget Usage</span>
          <span className="text-lg font-bold text-accent">${totalCost.toFixed(2)} <span className="text-sm font-normal text-muted">/ ${budget.toFixed(2)}</span></span>
        </div>
        <ProgressBar current={totalCost} max={budget} colorClass="bg-accent" />
      </div>
      
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
              <span className="text-accent bg-accent/10 px-2 py-1 rounded text-sm">${mdl.cost_usd.toFixed(3)}</span>
            </div>
            <div className="grid grid-cols-4 gap-3 text-xs">
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
  'active_sessions',
  'completed_sessions',
  'failed_sessions',
  'pending_sessions',
  'api_sessions_seen',
  'last_error'
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
  const [loading, setLoading] = useState(true);

  const [activeTab, setActiveTab] = useState<string>('');
  const [chartMetric, setChartMetric] = useState<'cost'|'tokens_in'|'tokens_out'|'reasoning'>('cost');
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterPriority, setFilterPriority] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState<string>('');

  const fetchData = useCallback(async () => {
    try {
      const ts = new Date().getTime();
      const [dataRes, sessionsRes, registryRes, ghIssuesRes] = await Promise.all([
        fetch(`/data.json?t=${ts}`).catch(() => null),
        fetch(`/active-sessions.json?t=${ts}`).catch(() => null),
        fetch(`/registry.json?t=${ts}`).catch(() => null),
        fetch(`/github-issues.json?t=${ts}`).catch(() => null)
      ]);

      if (dataRes?.ok) setHistoricalData(await dataRes.json());
      if (sessionsRes?.ok) setActiveSessions(await sessionsRes.json());
      if (ghIssuesRes?.ok) setGhIssues(await ghIssuesRes.json());
      
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
    const interval = setInterval(fetchData, 5000);
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
  
  const totalCost = todayData.reduce((acc, curr) => acc + curr.cost_usd, 0);
  const totalInputTokens = todayData.reduce((acc, curr) => acc + curr.input_tokens, 0);
  const totalOutputTokens = todayData.reduce((acc, curr) => acc + curr.output_tokens, 0);
  const totalReasoning = todayData.reduce((acc, curr) => acc + (curr.reasoning_tokens || 0), 0);

  let totalBudget = 0;
  const providersList = registry?.providers ? Object.entries(registry.providers).filter(([_, p]) => p.enabled) : [];
  providersList.forEach(([_, p]) => {
    totalBudget += p.daily_budget_usd || 0;
  });

  // --- Unified Task Board Processing ---
  const unifiedTasks: TaskItem[] = [];
  
  const parseIssueMetadata = (issue: any) => {
    const labels = issue.labels?.map((l: any) => typeof l === 'string' ? l : l.name) || [];
    const priority = labels.find((l: string) => ['low', 'medium', 'high', 'urgent'].includes(l.toLowerCase())) || 'medium';
    
    const body = issue.body || '';
    const taskMatches = body.match(/-\s*\[([ xX])\]/g) || [];
    const completed = taskMatches.filter((m: string) => m.toLowerCase().includes('x')).length;
    
    // Naming convention parsing
    let typeIcon = 'task';
    if (issue.title.includes('MF-StMa_')) typeIcon = 'Master';
    if (issue.title.includes('MF-StIs_')) typeIcon = 'Standard';
    if (issue.title.includes('MF-User_')) typeIcon = 'User';
    if (issue.title.includes('__MF-SubI_')) typeIcon = 'Sub';

    return { priority: priority.toLowerCase() as any, taskType: typeIcon, subIssues: { total: taskMatches.length, completed } };
  };

  const getUnifiedStatus = (task: any, source: 'JULES' | 'GITHUB' | 'REVIEW'): TaskItem['status'] => {
    // GH CLOSED is always COMPLETED
    if (task.github_state === 'CLOSED' || task.state === 'CLOSED') return 'COMPLETED';

    if (source === 'JULES' || task.jules_session_id) {
      if (task.jules_state === 'ERROR' || task.status === 'ERROR') return 'ERROR';
      if (task.jules_state === 'PENDING_INPUT' || task.status === 'PENDING_INPUT') return 'PENDING_INPUT';
      if (task.jules_state === 'IN_PROGRESS' || task.jules_state === 'RUNNING') return 'IN_PROGRESS';
      if (task.jules_state === 'IN_REVIEW' || task.status === 'IN_REVIEW') return 'IN_REVIEW';
    }

    if (source === 'REVIEW' || task.pr_url) {
      return 'IN_REVIEW';
    }

    return 'QUEUED';
  };

  if (activeSessions) {
    activeSessions.active_delegations?.forEach((d: any) => {
      const meta = parseIssueMetadata(d);
      unifiedTasks.push({
        id: d.issue_number?.toString() || '?',
        title: d.issue_title || 'Unknown Delegation',
        status: getUnifiedStatus(d, 'JULES'),
        gh_status: d.github_state || 'OPEN',
        priority: meta.priority,
        task_type: meta.taskType,
        sub_issues: meta.subIssues,
        jules_session_id: d.jules_session_id,
        timestamp: d.last_checked_at,
        raw: d
      });
    });

    activeSessions.decisions_pending?.forEach((d: any) => {
      const meta = parseIssueMetadata(d);
      unifiedTasks.push({
        id: d.issue_number?.toString() || 'Pending',
        title: d.issue_title || 'Waiting for Input',
        status: 'PENDING_INPUT',
        gh_status: 'OPEN',
        priority: meta.priority,
        task_type: meta.taskType,
        sub_issues: meta.subIssues,
        timestamp: new Date().toISOString(),
        raw: d
      });
    });

    activeSessions.review_queue?.forEach((d: any) => {
      const meta = parseIssueMetadata(d);
      unifiedTasks.push({
        id: d.issue_number?.toString() || 'PR',
        title: d.issue_title || 'Awaiting Review',
        status: getUnifiedStatus(d, 'REVIEW'),
        gh_status: 'OPEN',
        priority: meta.priority,
        task_type: meta.taskType,
        sub_issues: meta.subIssues,
        timestamp: new Date().toISOString(),
        raw: d
      });
    });
  }

  ghIssues.forEach((issue: any) => {
    const issueIdStr = issue.number.toString();
    const alreadyTracked = unifiedTasks.find(t => t.id === issueIdStr);
    
    if (!alreadyTracked) {
      const meta = parseIssueMetadata(issue);
      unifiedTasks.push({
        id: issueIdStr,
        title: issue.title,
        status: getUnifiedStatus(issue, 'GITHUB'),
        gh_status: issue.state,
        priority: meta.priority,
        task_type: meta.taskType,
        sub_issues: meta.subIssues,
        timestamp: issue.updatedAt,
        raw: issue
      });
    }
  });

  const filteredTasks = unifiedTasks.filter(task => {
    const matchesStatus = filterStatus === 'all' || task.status === filterStatus;
    const matchesPriority = filterPriority === 'all' || task.priority === filterPriority;
    const matchesSearch = task.title.toLowerCase().includes(searchQuery.toLowerCase()) || task.id.includes(searchQuery);
    return matchesStatus && matchesPriority && matchesSearch;
  });

  const statusWeight = { 'ERROR': 6, 'IN_PROGRESS': 5, 'PENDING_INPUT': 4, 'IN_REVIEW': 3, 'QUEUED': 2, 'COMPLETED': 1 };
  filteredTasks.sort((a, b) => statusWeight[b.status] - statusWeight[a.status]);

  const activeCount = unifiedTasks.filter(t => t.status === 'IN_PROGRESS').length;

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
    if (chartMetric === 'cost') val = curr.cost_usd;
    if (chartMetric === 'tokens_in') val = curr.input_tokens;
    if (chartMetric === 'tokens_out') val = curr.output_tokens;
    if (chartMetric === 'reasoning') val = curr.reasoning_tokens || 0;

    dayData[key] = (dayData[key] || 0) + val;
  });

  const chartData = Array.from(chartMap.values()).sort((a: any, b: any) => a.date.localeCompare(b.date)).slice(-14);
  const modelsArray = Array.from(modelsInChart);

  const getStatusColor = (status: string) => {
    switch(status) {
      case 'IN_PROGRESS': return 'bg-green-500/20 text-green-400 border-green-500/30';
      case 'ERROR': return 'bg-red-500/20 text-red-400 border-red-500/30';
      case 'PENDING_INPUT': return 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30';
      case 'IN_REVIEW': return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
      case 'QUEUED': return 'bg-gray-500/20 text-gray-400 border-gray-500/30';
      case 'COMPLETED': return 'bg-purple-500/20 text-purple-400 border-purple-500/30';
      default: return 'bg-surface text-white border-white/10';
    }
  };

  const getStatusLabel = (task: TaskItem) => {
    const raw = task.raw || {};
    switch(task.status) {
      case 'IN_PROGRESS': return 'Jules: Working';
      case 'ERROR': return `Error: ${raw.message || 'Unknown'}`;
      case 'PENDING_INPUT': return 'Input Required';
      case 'IN_REVIEW': {
        if (raw.pr_checks_status === 'FAILURE') return 'Review: Checks Failed';
        if (raw.pr_checks_status === 'SUCCESS') return 'Review: Ready to Merge';
        return 'Review: Pending';
      }
      case 'QUEUED': return 'GitHub: Open / Queued';
      case 'COMPLETED': return 'GitHub: Completed / Closed';
      default: return task.status;
    }
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
            <div className={`w-2 h-2 rounded-full ${activeCount > 0 ? 'bg-green-500 animate-pulse' : 'bg-blue-500'}`} />
            <span className="text-sm font-medium text-white">{activeCount > 0 ? `${activeCount} Tasks Running` : 'System Idle'}</span>
          </div>
          <div className="text-[10px] text-muted-foreground font-mono">Last Sync: {new Date().toLocaleTimeString()}</div>
        </div>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-10">
        <StatCard 
          title="Daily Quota Usage (Total USD)" 
          value={`$${totalCost.toFixed(2)}`} 
          highlightClass="text-accent"
          icon={DollarSign}
          tooltip="Gesamte geschätzte bzw. echte USD-Kosten aller aufgerufenen LLMs heute."
          subtitle={
            <div>
              <div className="mb-1">Limit: ${totalBudget.toFixed(2)}</div>
              {totalBudget > 0 && <ProgressBar current={totalCost} max={totalBudget} colorClass="bg-accent" />}
            </div>
          }
        />
        <StatCard 
          title="Tokens Processed" 
          value={((totalInputTokens + totalOutputTokens) / 1000).toFixed(1) + 'k'} 
          icon={Cpu}
          tooltip="Die Summe aller gelesenen (Input) und generierten (Output) Tokens heute."
          subtitle={
            <div className="flex justify-between mt-1 text-xs">
              <span className="text-primary">In: {(totalInputTokens / 1000).toFixed(1)}k</span>
              <span className="text-secondary">Out: {(totalOutputTokens / 1000).toFixed(1)}k</span>
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
          title="System Task Queue" 
          value={unifiedTasks.length} 
          icon={Layers}
          tooltip="Alle aktiven und wartenden Aufgaben im Autopilot-System."
          subtitle={
            <div className="flex gap-3 mt-1 text-xs">
              <span className="text-green-400">{activeCount} Running</span>
              <span className="text-yellow-400">{unifiedTasks.filter(t=>t.status==='PENDING_INPUT').length} Pending</span>
            </div>
          }
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
              Historical Quota Burn
            </h2>
            <div className="flex gap-2">
              <select 
                value={chartMetric} 
                onChange={e => setChartMetric(e.target.value as any)}
                className="bg-surface border border-white/10 rounded-lg px-3 py-1 text-sm text-white focus:outline-none focus:border-primary"
              >
                <option value="cost">Cost (USD)</option>
                <option value="tokens_in">Input Tokens</option>
                <option value="tokens_out">Output Tokens</option>
                <option value="reasoning">Reasoning Tokens</option>
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
                <YAxis stroke="#94a3b8" fontSize={12} tickFormatter={(val) => chartMetric === 'cost' ? `$${val}` : `${(val/1000).toFixed(0)}k`} />
                <Tooltip 
                  contentStyle={{ backgroundColor: '#151520', borderColor: '#2e2e3d', borderRadius: '12px' }}
                  itemStyle={{ color: '#f8fafc' }}
                  formatter={(value: any) => chartMetric === 'cost' ? `$${Number(value).toFixed(2)}` : Number(value).toLocaleString()}
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
      
      {/* UNIFIED TASK BOARD */}
      {activeSessions && (
        <div className="glass-card p-6 animate-slide-up" style={{ animationDelay: '200ms' }}>
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-6 gap-4">
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <RefreshCw size={20} className="text-secondary" />
              Unified Task Board (Sync: {ghIssues.length > 0 ? 'Active' : 'Initializing...'})
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
                <option value="IN_PROGRESS">In Progress</option>
                <option value="PENDING_INPUT">Pending Input</option>
                <option value="ERROR">Blocked</option>
                <option value="IN_REVIEW">In Review</option>
                <option value="QUEUED">Queued</option>
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
              <div className="text-xs bg-surface px-3 py-2 rounded text-muted border border-white/5">Matches: {filteredTasks.length}</div>
            </div>
          </div>
          
          <div className="grid grid-cols-1 gap-3">
            {filteredTasks.length === 0 && (
              <div className="text-center py-10 text-muted border border-dashed border-white/10 rounded-xl">
                No tasks matching your filters.
              </div>
            )}
            
            {filteredTasks.map((task, idx) => (
              <div key={idx} className="bg-surface/30 rounded-xl p-4 border border-white/5 flex flex-col md:flex-row md:items-center justify-between gap-4 hover:bg-surface/50 transition-colors">
                
                <div className="flex items-center gap-4 flex-1 overflow-hidden">
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
                      {task.priority && (
                        <span className={`text-[10px] uppercase font-black px-1.5 py-0.5 rounded ${
                          task.priority === 'urgent' ? 'bg-red-500 text-white' : 
                          task.priority === 'high' ? 'bg-orange-500 text-white' : 
                          task.priority === 'medium' ? 'bg-blue-500 text-white' : 'bg-gray-500 text-white'
                        }`}>
                          {task.priority}
                        </span>
                      )}
                      {task.task_type && (
                        <span className="text-[10px] text-muted-foreground bg-white/5 px-1.5 py-0.5 rounded border border-white/5 italic">
                          {task.task_type}
                        </span>
                      )}
                      {task.sub_issues && task.sub_issues.total > 0 && (
                        <span className="text-[10px] text-primary flex items-center gap-1 font-bold">
                          <Layers size={10} /> Sub-Tasks: {task.sub_issues.completed}/{task.sub_issues.total}
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
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
