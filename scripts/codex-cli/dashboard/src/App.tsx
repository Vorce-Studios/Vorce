import { useEffect, useState } from 'react';
import { XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, AreaChart, Area } from 'recharts';
import { Activity, BrainCircuit, Cpu, DollarSign, Database, Zap, RefreshCw, Layers, AlertTriangle, CheckCircle, Clock } from 'lucide-react';

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

interface ActiveSession {
  issue_number: number;
  issue_title?: string;
  jules_state: string;
  last_checked_at: string;
  jules_session_id: string;
  delegated_at: string;
}

interface ActiveSessionsData {
  last_heartbeat: string;
  active_delegations: ActiveSession[];
  review_queue: any[];
  decisions_pending: any[];
  error_log: any[];
}

interface RegistryData {
  providers: {
    [key: string]: {
      enabled: boolean;
      daily_budget_usd: number;
      daily_limit: number;
      purpose: string[];
      models?: { [key: string]: { name: string, estimated_cost_per_call_usd: number } };
    }
  }
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
    <div className="glass-card p-5 border border-white/5">
      <div className="flex justify-between items-start mb-3">
        <div>
          <h3 className="text-lg font-bold text-white capitalize">{name.replace('_', ' ')}</h3>
          {providerReg?.purpose && (
            <div className="flex gap-1 mt-1 flex-wrap">
              {providerReg.purpose.map((p: string) => (
                <span key={p} className="text-[10px] uppercase tracking-wider bg-white/5 text-muted px-2 py-0.5 rounded border border-white/10">{p}</span>
              ))}
            </div>
          )}
        </div>
        <div className="px-3 py-1 rounded-full bg-primary/20 text-primary text-xs font-semibold">
          {totalCalls} / {limit} calls
        </div>
      </div>
      
      <div className="mb-4">
        <div className="flex justify-between items-end">
          <span className="text-muted text-xs">Budget Usage</span>
          <span className="text-sm font-bold text-accent">${totalCost.toFixed(2)} <span className="text-xs font-normal text-muted">/ ${budget.toFixed(2)}</span></span>
        </div>
        <ProgressBar current={totalCost} max={budget} colorClass="bg-accent" />
      </div>
      
      <div className="space-y-2">
        <div className="text-xs font-semibold text-white/50 uppercase tracking-wider border-b border-white/10 pb-1 mb-2">Model Breakdown</div>
        
        {modelsData.length === 0 && (
          <div className="text-xs text-muted italic">No usage recorded today.</div>
        )}

        {modelsData.map((mdl, idx) => {
          return (
            <div key={idx} className="bg-surface/30 rounded p-2 border border-white/5 text-xs">
              <div className="flex justify-between font-medium text-white mb-1">
                <span>{mdl.model_name}</span>
                <span className="text-accent">${mdl.cost_usd.toFixed(3)}</span>
              </div>
              <div className="grid grid-cols-4 gap-1 text-[10px]">
                <div className="flex flex-col"><span className="text-muted">In/Out</span><span>{formatTokens(mdl.input_tokens)}/{formatTokens(mdl.output_tokens)}</span></div>
                <div className="flex flex-col"><span className="text-muted">Cached</span><span className="text-secondary">{formatTokens(mdl.cached_tokens)}</span></div>
                <div className="flex flex-col"><span className="text-muted">Reasoning</span><span className="text-primary">{formatTokens(mdl.reasoning_tokens)}</span></div>
                <div className="flex flex-col"><span className="text-muted">Tools</span><span className="text-green-400">{formatTokens(mdl.tool_tokens)}</span></div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  );
}

export default function App() {
  const [historicalData, setHistoricalData] = useState<QuotaData[]>([]);
  const [activeSessions, setActiveSessions] = useState<ActiveSessionsData | null>(null);
  const [registry, setRegistry] = useState<RegistryData | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchData = async () => {
    try {
      const [dataRes, sessionsRes, registryRes] = await Promise.all([
        fetch('/data.json').catch(() => null),
        fetch('/active-sessions.json').catch(() => null),
        fetch('/registry.json').catch(() => null)
      ]);

      if (dataRes?.ok) setHistoricalData(await dataRes.json());
      if (sessionsRes?.ok) setActiveSessions(await sessionsRes.json());
      if (registryRes?.ok) setRegistry(await registryRes.json());
    } catch (e) {
      console.error("Error fetching data", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 15000);
    return () => clearInterval(interval);
  }, []);

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
  const todayData = historicalData.filter(d => d.date === today);
  
  const totalCost = todayData.reduce((acc, curr) => acc + curr.cost_usd, 0);
  const totalInputTokens = todayData.reduce((acc, curr) => acc + curr.input_tokens, 0);
  const totalOutputTokens = todayData.reduce((acc, curr) => acc + curr.output_tokens, 0);
  const totalReasoning = todayData.reduce((acc, curr) => acc + (curr.reasoning_tokens || 0), 0);

  let totalBudget = 0;
  const providersList = registry?.providers ? Object.entries(registry.providers) : [];
  providersList.forEach(([_, p]) => {
    totalBudget += p.daily_budget_usd || 0;
  });

  const activeCount = activeSessions?.active_delegations?.length || 0;
  const pendingCount = activeSessions?.decisions_pending?.length || 0;
  const reviewCount = activeSessions?.review_queue?.length || 0;
  const errorCount = activeSessions?.error_log?.length || 0;
  const totalTasks = activeCount + pendingCount + reviewCount;

  // Aggregate cost by date for the area chart
  const chartMap = new Map();
  historicalData.forEach(curr => {
    const cost = chartMap.get(curr.date) || 0;
    chartMap.set(curr.date, cost + curr.cost_usd);
  });
  const chartData = Array.from(chartMap.entries()).map(([date, cost]) => ({ date, cost })).sort((a, b) => a.date.localeCompare(b.date)).slice(-14);

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
        <div className="flex gap-4">
          {errorCount > 0 && (
            <div className="glass px-4 py-2 rounded-full flex items-center gap-3 border-red-500/30">
              <AlertTriangle size={16} className="text-red-500 animate-pulse" />
              <span className="text-sm font-medium text-red-500">{errorCount} Errors</span>
            </div>
          )}
          <div className="glass px-4 py-2 rounded-full flex items-center gap-3">
            <div className={`w-2 h-2 rounded-full ${activeCount > 0 ? 'bg-green-500 animate-pulse' : 'bg-blue-500'}`} />
            <span className="text-sm font-medium text-white">{activeCount > 0 ? 'Tasks Running' : 'System Idle'}</span>
          </div>
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
          value={totalTasks} 
          icon={Layers}
          tooltip="Aktive Aufgaben im Autopilot-System: Running (Live Jules), Pending (Warten auf Input), Review (PR-Abnahme)."
          subtitle={
            <div className="flex gap-3 mt-1 text-xs">
              <span className="text-green-400">{activeCount} Active</span>
              <span className="text-yellow-400">{pendingCount} Pending</span>
              <span className="text-blue-400">{reviewCount} Review</span>
            </div>
          }
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 mb-10">
        <div className="lg:col-span-2 glass-card p-6 animate-slide-up">
          <div className="flex justify-between items-center mb-6">
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <Database size={20} className="text-primary" />
              Historical Quota Burn (Cost)
            </h2>
            <div className="text-xs text-muted italic">
              {chartData.length <= 1 ? "Nur 1 Datenpunkt: Historie startet heute." : "Zeigt den Kostenverlauf der letzten 14 Tage."}
            </div>
          </div>
          <div className="h-72 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                <defs>
                  <linearGradient id="colorCost" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#6366f1" stopOpacity={0.8}/>
                    <stop offset="95%" stopColor="#6366f1" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#ffffff10" vertical={false} />
                <XAxis dataKey="date" stroke="#94a3b8" fontSize={12} tickMargin={10} />
                <YAxis stroke="#94a3b8" fontSize={12} tickFormatter={(val) => `$${val}`} />
                <Tooltip 
                  contentStyle={{ backgroundColor: '#151520', borderColor: '#2e2e3d', borderRadius: '12px' }}
                  itemStyle={{ color: '#f8fafc' }}
                />
                <Area type="monotone" dataKey="cost" stroke="#6366f1" strokeWidth={3} fillOpacity={1} fill="url(#colorCost)" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="glass-card p-6 animate-slide-up" style={{ animationDelay: '100ms' }}>
          <h2 className="text-xl font-bold text-white mb-6 flex items-center gap-2">
            <Zap size={20} className="text-accent" />
            Provider Distribution
          </h2>
          <div className="flex flex-col gap-4 overflow-y-auto max-h-[350px] pr-2 custom-scrollbar">
            {providersList.map(([pName, pConfig]) => {
              if (!pConfig.enabled) return null;
              const providerData = todayData.filter(d => d.provider_name === pName);
              return <ProviderCard key={pName} name={pName} providerReg={pConfig} modelsData={providerData} />
            })}
          </div>
        </div>
      </div>
      
      {activeSessions && (
        <div className="glass-card p-6 animate-slide-up" style={{ animationDelay: '200ms' }}>
          <h2 className="text-xl font-bold text-white mb-6 flex items-center gap-2">
            <RefreshCw size={20} className="text-secondary" />
            Autopilot State Control
          </h2>
          
          <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
            
            <div className="bg-surface/30 rounded-xl p-4 border border-white/5 h-full">
              <h3 className="font-semibold text-white mb-4 flex items-center justify-between">
                <span>Running Sessions</span>
                <span className="bg-green-500/20 text-green-400 px-2 py-0.5 rounded-full text-xs">{activeCount}</span>
              </h3>
              <div className="space-y-3">
                {activeCount === 0 && <div className="text-sm text-muted">No active sessions.</div>}
                {activeSessions.active_delegations?.map((session, idx) => (
                  <div key={idx} className="bg-background rounded-lg p-3 border border-white/5 relative overflow-hidden">
                    <div className="absolute left-0 top-0 bottom-0 w-1 bg-green-500"></div>
                    <div className="flex justify-between items-start mb-1">
                      <span className="font-mono text-xs text-primary">ID: {session.jules_session_id || 'N/A'}</span>
                      <span className="text-xs text-muted">Issue: #{session.issue_number}</span>
                    </div>
                    <div className="text-sm text-white font-medium mb-2 truncate" title={session.issue_title}>{session.issue_title || 'No Title'}</div>
                    <div className="flex items-center gap-2">
                      <div className={`w-2 h-2 rounded-full ${session.jules_state === 'RUNNING' ? 'bg-green-500 animate-pulse' : 'bg-yellow-500'}`} />
                      <span className="text-xs text-white">{session.jules_state}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            <div className="bg-surface/30 rounded-xl p-4 border border-white/5 h-full">
              <h3 className="font-semibold text-white mb-4 flex items-center justify-between">
                <span>Pending Decisions</span>
                <span className="bg-yellow-500/20 text-yellow-400 px-2 py-0.5 rounded-full text-xs">{pendingCount}</span>
              </h3>
              <div className="space-y-3">
                {pendingCount === 0 && <div className="text-sm text-muted">No decisions pending.</div>}
                {activeSessions.decisions_pending?.map((pending, idx) => (
                  <div key={idx} className="bg-background rounded-lg p-3 border border-white/5 relative overflow-hidden">
                    <div className="absolute left-0 top-0 bottom-0 w-1 bg-yellow-500"></div>
                    <div className="text-sm text-white font-medium mb-1">Waiting on Input</div>
                    <div className="text-xs text-muted font-mono">{JSON.stringify(pending)}</div>
                  </div>
                ))}
              </div>
            </div>

            <div className="bg-surface/30 rounded-xl p-4 border border-white/5 h-full flex flex-col gap-6">
              <div>
                <h3 className="font-semibold text-white mb-4 flex items-center justify-between">
                  <span>Review Queue</span>
                  <span className="bg-blue-500/20 text-blue-400 px-2 py-0.5 rounded-full text-xs">{reviewCount}</span>
                </h3>
                <div className="space-y-3">
                  {reviewCount === 0 && <div className="text-sm text-muted">No PRs in review queue.</div>}
                  {activeSessions.review_queue?.map((rev, idx) => (
                    <div key={idx} className="flex items-center gap-2 text-sm text-white bg-background p-2 rounded">
                      <CheckCircle size={14} className="text-blue-400" />
                      <span className="truncate">{JSON.stringify(rev)}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div>
                <h3 className="font-semibold text-white mb-4 flex items-center justify-between">
                  <span>Recent Errors</span>
                  <span className="bg-red-500/20 text-red-400 px-2 py-0.5 rounded-full text-xs">{errorCount}</span>
                </h3>
                <div className="space-y-3">
                  {errorCount === 0 && <div className="text-sm text-muted">No recent errors detected.</div>}
                  {activeSessions.error_log?.slice(0, 3).map((err: any, idx: number) => (
                    <div key={idx} className="bg-red-500/10 rounded-lg p-2 border border-red-500/20">
                      <div className="text-xs text-red-400 font-bold mb-1 flex items-center gap-1">
                        <Clock size={12} /> {new Date(err.timestamp).toLocaleTimeString()}
                      </div>
                      <div className="text-xs text-white/80">{err.message}</div>
                    </div>
                  ))}
                </div>
              </div>
            </div>

          </div>
        </div>
      )}
    </div>
  );
}
