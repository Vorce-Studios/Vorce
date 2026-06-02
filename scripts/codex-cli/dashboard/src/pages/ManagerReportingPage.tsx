import { useState } from 'react';
import {
  Clock,
  DollarSign,
  CheckCircle2,
  Layers,
  Users,
  Zap
} from 'lucide-react';
import type { QuotaRegistry, ActiveSessions, GitHubIssue, PullRequest } from '../types';

interface ManagerReportingPageProps {
  registry: QuotaRegistry;
  sessions: ActiveSessions;
  issues: GitHubIssue[];
  pullRequests: PullRequest[];
  history: any[];
}

export default function ManagerReportingPage({ registry, sessions, issues }: ManagerReportingPageProps) {
  const [timeRange, setTimeRange] = useState<'today' | '7d' | '30d'>('7d');
  const [selectedLabel, setSelectedLabel] = useState<string>('all');

  // --- 1. Berechnungen für Issues & PRs ---
  const totalIssues = issues.length;
  const closedIssues = issues.filter(i => i.state.toLowerCase() === 'closed').length;
  const resolutionRate = totalIssues > 0 ? Math.round((closedIssues / totalIssues) * 100) : 0;

  // Klassifizierung nach Label
  const bugIssues = issues.filter(i => i.labels.some(l => l.name.toLowerCase().includes('bug')));
  const featureIssues = issues.filter(i => i.labels.some(l => l.name.toLowerCase().includes('feature') || l.name.toLowerCase().includes('enhancement')));
  const julesTasks = issues.filter(i => i.labels.some(l => l.name.toLowerCase().includes('jules')));

  const openBugs = bugIssues.filter(i => i.state.toLowerCase() === 'open').length;
  const openFeatures = featureIssues.filter(i => i.state.toLowerCase() === 'open').length;
  const openJules = julesTasks.filter(i => i.state.toLowerCase() === 'open').length;

  // Lösungszeit berechnen (createdAt bis updatedAt bei geschlossenen Issues als Näherung)
  const closedIssuesWithDuration = issues.filter(i => i.state.toLowerCase() === 'closed' && i.createdAt && i.updatedAt);
  let avgResolutionTimeHours = 0;
  if (closedIssuesWithDuration.length > 0) {
    const totalHours = closedIssuesWithDuration.reduce((acc, issue) => {
      const created = new Date(issue.createdAt).getTime();
      const updated = new Date(issue.updatedAt).getTime();
      return acc + (updated - created) / (1000 * 60 * 60);
    }, 0);
    avgResolutionTimeHours = Math.round(totalHours / closedIssuesWithDuration.length);
  }

  // --- 2. Kosten & Quoten ---
  let totalCostToday = 0;
  const providerStats: { name: string; calls: number; cost: number; limit: number; budget: number }[] = [];

  if (registry.providers) {
    Object.entries(registry.providers).forEach(([name, provider]) => {
      const calls = provider.usage_today?.calls || 0;
      const cost = provider.usage_today?.estimated_cost_usd || 0;
      totalCostToday += cost;

      providerStats.push({
        name,
        calls,
        cost,
        limit: provider.daily_limit || 0,
        budget: provider.daily_budget_usd || 0
      });
    });
  }

  // Dual-CEO Budget Limit (Default: $10/Tag)
  const dailyBudget = 10.0;
  const budgetPercentage = dailyBudget > 0 ? Math.min(100, Math.round((totalCostToday / dailyBudget) * 100)) : 0;

  // --- 3. Deliberation-Statistiken ---
  const deliberations = sessions.deliberation_log || [];
  const totalDeliberations = deliberations.length;
  const consensusDeliberations = deliberations.filter(d => d.consensus_reached).length;
  const consensusRate = totalDeliberations > 0 ? Math.round((consensusDeliberations / totalDeliberations) * 100) : 0;

  let avgDurationMs = 0;
  let avgRounds = 0;
  if (totalDeliberations > 0) {
    const totalDuration = deliberations.reduce((acc, d) => acc + (d.total_duration_ms || 0), 0);
    avgDurationMs = Math.round(totalDuration / totalDeliberations);

    const totalRounds = deliberations.reduce((acc, d) => acc + (d.rounds?.length || d.phases_completed || 0), 0);
    avgRounds = Math.round((totalRounds / totalDeliberations) * 10) / 10;
  }

  // Letzte erledigte Sessions
  const completedSessions = sessions.completed_this_session || [];

  // Filterung aller Labels für Dropdown
  const allLabels = Array.from(
    new Set(issues.flatMap(i => i.labels.map(l => l.name)))
  ).sort();

  const filteredIssues = selectedLabel === 'all'
    ? issues
    : issues.filter(i => i.labels.some(l => l.name === selectedLabel));

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-slate-900/30 p-5 rounded-xl border border-slate-800">
        <div>
          <h2 className="text-xl font-bold text-white tracking-wide">Manager Reporting Dashboard</h2>
          <p className="text-xs text-slate-400">Übersicht über Produktivität, CEO-Verhalten und Kostenmetriken.</p>
        </div>
        <div className="flex items-center gap-2">
          <select
            value={selectedLabel}
            onChange={(e) => setSelectedLabel(e.target.value)}
            className="bg-slate-950 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-purple-500"
          >
            <option value="all">Alle Themen / Labels</option>
            {allLabels.map(l => (
              <option key={l} value={l}>{l}</option>
            ))}
          </select>
          <div className="flex rounded-lg border border-slate-800 p-0.5 bg-slate-950">
            {(['today', '7d', '30d'] as const).map(range => (
              <button
                key={range}
                onClick={() => setTimeRange(range)}
                className={`px-3 py-1 text-[10px] font-semibold rounded-md transition-all duration-150 ${
                  timeRange === range
                    ? 'bg-purple-600 text-white shadow-md'
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {range === 'today' ? 'Heute' : range === '7d' ? '7 Tage' : '30 Tage'}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* KPI Cards Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Card 1: Lösungsrate */}
        <div className="bg-slate-900/40 p-4 rounded-xl border border-slate-800 flex items-start gap-4">
          <div className="p-2.5 bg-green-500/10 rounded-lg text-green-400">
            <CheckCircle2 className="w-5 h-5" />
          </div>
          <div>
            <p className="text-xs text-slate-400 font-medium">Issue Lösungsrate</p>
            <h3 className="text-2xl font-bold text-white mt-1">{resolutionRate}%</h3>
            <p className="text-[10px] text-slate-400 mt-1">
              <span className="text-green-400 font-semibold">{closedIssues}</span> von {totalIssues} gelöst
            </p>
          </div>
        </div>

        {/* Card 2: Bearbeitungszeit */}
        <div className="bg-slate-900/40 p-4 rounded-xl border border-slate-800 flex items-start gap-4">
          <div className="p-2.5 bg-cyan-500/10 rounded-lg text-cyan-400">
            <Clock className="w-5 h-5" />
          </div>
          <div>
            <p className="text-xs text-slate-400 font-medium">Ø Lösungszeit</p>
            <h3 className="text-2xl font-bold text-white mt-1">
              {avgResolutionTimeHours > 0 ? `${avgResolutionTimeHours}h` : 'N/A'}
            </h3>
            <p className="text-[10px] text-slate-400 mt-1">
              basierend auf {closedIssuesWithDuration.length} geschlossenen Issues
            </p>
          </div>
        </div>

        {/* Card 3: CEO Consensus Rate */}
        <div className="bg-slate-900/40 p-4 rounded-xl border border-slate-800 flex items-start gap-4">
          <div className="p-2.5 bg-purple-500/10 rounded-lg text-purple-400">
            <Users className="w-5 h-5" />
          </div>
          <div>
            <p className="text-xs text-slate-400 font-medium">CEO Consensus Rate</p>
            <h3 className="text-2xl font-bold text-white mt-1">{consensusRate}%</h3>
            <p className="text-[10px] text-slate-400 mt-1">
              <span className="text-purple-400 font-semibold">{consensusDeliberations}</span> von {totalDeliberations} Einigungen
            </p>
          </div>
        </div>

        {/* Card 4: Kosten Heute */}
        <div className="bg-slate-900/40 p-4 rounded-xl border border-slate-800 flex items-start gap-4">
          <div className="p-2.5 bg-yellow-500/10 rounded-lg text-yellow-400">
            <DollarSign className="w-5 h-5" />
          </div>
          <div>
            <p className="text-xs text-slate-400 font-medium">Kosten Heute</p>
            <h3 className="text-2xl font-bold text-white mt-1">${totalCostToday.toFixed(3)}</h3>
            <p className="text-[10px] text-slate-400 mt-1">
              <span className="text-yellow-400 font-semibold">{budgetPercentage}%</span> des $10 Budgets verbraucht
            </p>
          </div>
        </div>
      </div>

      {/* Main Section Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left Column: Themenanalyse & Provider Effizienz (2/3 Breite) */}
        <div className="lg:col-span-2 space-y-6">
          {/* Section: Themenbasierte Analyse */}
          <div className="bg-slate-900/40 rounded-xl border border-slate-800 p-5">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <Layers className="w-4 h-4 text-purple-400" />
                <h3 className="text-sm font-bold text-white tracking-wide">Themenbasierte Fortschrittsanalyse</h3>
              </div>
              <span className="text-[10px] text-slate-500 font-medium">Klassifizierung über Labels</span>
            </div>

            <div className="space-y-4">
              {/* Bugs Category */}
              <div className="bg-slate-950/40 border border-slate-800/60 rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold text-red-400">Bugs & Stabilität</span>
                  <span className="text-xs text-slate-400">{bugIssues.length - openBugs}/{bugIssues.length} Gelöst</span>
                </div>
                <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
                  <div
                    className="bg-red-500 h-1.5 rounded-full transition-all duration-300"
                    style={{ width: `${bugIssues.length > 0 ? ((bugIssues.length - openBugs) / bugIssues.length) * 100 : 0}%` }}
                  />
                </div>
                <div className="flex gap-4 mt-2 text-[10px] text-slate-500">
                  <span>Offen: <strong className="text-red-400">{openBugs}</strong></span>
                  <span>Gelöst: <strong className="text-slate-300">{bugIssues.length - openBugs}</strong></span>
                </div>
              </div>

              {/* Features Category */}
              <div className="bg-slate-950/40 border border-slate-800/60 rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold text-cyan-400">Features & Erweiterungen</span>
                  <span className="text-xs text-slate-400">{featureIssues.length - openFeatures}/{featureIssues.length} Gelöst</span>
                </div>
                <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
                  <div
                    className="bg-cyan-500 h-1.5 rounded-full transition-all duration-300"
                    style={{ width: `${featureIssues.length > 0 ? ((featureIssues.length - openFeatures) / featureIssues.length) * 100 : 0}%` }}
                  />
                </div>
                <div className="flex gap-4 mt-2 text-[10px] text-slate-500">
                  <span>Offen: <strong className="text-cyan-400">{openFeatures}</strong></span>
                  <span>Gelöst: <strong className="text-slate-300">{featureIssues.length - openFeatures}</strong></span>
                </div>
              </div>

              {/* Jules Tasks Category */}
              <div className="bg-slate-950/40 border border-slate-800/60 rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold text-purple-400">Jules Delegationen (`jules-task`)</span>
                  <span className="text-xs text-slate-400">{julesTasks.length - openJules}/{julesTasks.length} Gelöst</span>
                </div>
                <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
                  <div
                    className="bg-purple-500 h-1.5 rounded-full transition-all duration-300"
                    style={{ width: `${julesTasks.length > 0 ? ((julesTasks.length - openJules) / julesTasks.length) * 100 : 0}%` }}
                  />
                </div>
                <div className="flex gap-4 mt-2 text-[10px] text-slate-500">
                  <span>Aktiv/Offen: <strong className="text-purple-400">{openJules}</strong></span>
                  <span>Gelöst: <strong className="text-slate-300">{julesTasks.length - openJules}</strong></span>
                </div>
              </div>
            </div>
          </div>

          {/* Section: Provider Quoten & Effizienz */}
          <div className="bg-slate-900/40 rounded-xl border border-slate-800 p-5">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <DollarSign className="w-4 h-4 text-yellow-400" />
                <h3 className="text-sm font-bold text-white tracking-wide">Provider Quoten & Kosten-Effizienz</h3>
              </div>
              <span className="text-[10px] text-slate-500 font-medium">Heute aktive API-Calls</span>
            </div>

            <div className="space-y-4">
              {providerStats.map(stat => {
                const isJules = stat.name === 'jules';
                const limitStr = isJules ? `${stat.limit} Sessions` : `$${stat.budget?.toFixed(2)} Budget`;
                const usageStr = isJules ? `${stat.calls} gestartet` : `$${stat.cost?.toFixed(3)} verbraucht`;
                const progressPct = isJules
                  ? (stat.limit > 0 ? Math.min(100, Math.round((stat.calls / stat.limit) * 100)) : 0)
                  : (stat.budget > 0 ? Math.min(100, Math.round((stat.cost / stat.budget) * 100)) : 0);

                return (
                  <div key={stat.name} className="border border-slate-800 rounded-lg p-3 bg-slate-950/20">
                    <div className="flex items-center justify-between mb-1.5">
                      <div className="flex items-center gap-2">
                        <div className={`w-2 h-2 rounded-full ${stat.calls > 0 ? 'bg-green-500 animate-pulse' : 'bg-slate-700'}`} />
                        <span className="text-xs font-semibold uppercase text-slate-200">{stat.name.replace('_', ' ')}</span>
                      </div>
                      <span className="text-xs text-slate-400 font-medium">{usageStr} / {limitStr}</span>
                    </div>

                    <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
                      <div
                        className={`h-1.5 rounded-full transition-all duration-300 ${
                          progressPct > 90 ? 'bg-red-500' : progressPct > 70 ? 'bg-yellow-500' : 'bg-purple-600'
                        }`}
                        style={{ width: `${progressPct}%` }}
                      />
                    </div>

                    <div className="flex justify-between items-center mt-2 text-[9px] text-slate-500">
                      <span>Gesamt-Aufrufe heute: <strong className="text-slate-300">{stat.calls}</strong></span>
                      {!isJules && <span>Ø Kosten/Aufruf: <strong className="text-slate-300">${stat.calls > 0 ? (stat.cost / stat.calls).toFixed(4) : '0.0000'}</strong></span>}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Right Column: Deliberation Insights & CEO Chat (1/3 Breite) */}
        <div className="space-y-6">
          {/* Section: CEO Deliberation Insights */}
          <div className="bg-slate-900/40 rounded-xl border border-slate-800 p-5">
            <div className="flex items-center gap-2 mb-4">
              <Zap className="w-4 h-4 text-purple-400" />
              <h3 className="text-sm font-bold text-white tracking-wide">CEO Deliberation Insights</h3>
            </div>

            <div className="space-y-3.5">
              <div className="flex justify-between items-center py-2 border-b border-slate-800">
                <span className="text-xs text-slate-400">Einigungsrate (Consensus)</span>
                <span className="text-xs font-semibold text-white">{consensusRate}%</span>
              </div>
              <div className="flex justify-between items-center py-2 border-b border-slate-800">
                <span className="text-xs text-slate-400">Durchschnittliche Runden</span>
                <span className="text-xs font-semibold text-white">{avgRounds}</span>
              </div>
              <div className="flex justify-between items-center py-2 border-b border-slate-800">
                <span className="text-xs text-slate-400">Ø Abstimmungsdauer</span>
                <span className="text-xs font-semibold text-white">
                  {avgDurationMs > 0 ? `${(avgDurationMs / 1000).toFixed(1)}s` : 'N/A'}
                </span>
              </div>
              <div className="flex justify-between items-center py-2">
                <span className="text-xs text-slate-400">Aktive Sitzungen</span>
                <span className="text-xs font-semibold text-white">
                  {sessions.active_delegations?.length || 0}
                </span>
              </div>
            </div>
          </div>

          {/* Section: Letzte fertiggestellte Tasks */}
          <div className="bg-slate-900/40 rounded-xl border border-slate-800 p-5">
            <div className="flex items-center gap-2 mb-4">
              <CheckCircle2 className="w-4 h-4 text-green-400" />
              <h3 className="text-sm font-bold text-white tracking-wide">Zuletzt erledigt</h3>
            </div>

            {completedSessions.length === 0 ? (
              <div className="text-center py-6 text-xs text-slate-500">
                Keine abgeschlossenen Tasks in dieser Sitzung.
              </div>
            ) : (
              <div className="space-y-3 max-h-[300px] overflow-y-auto pr-1">
                {completedSessions.map((session, idx) => (
                  <div key={idx} className="border-b border-slate-800 pb-2.5 last:border-b-0 last:pb-0">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex-1 min-w-0">
                        <span className="text-[10px] font-semibold text-green-400">Issue #{session.issue_number}</span>
                        <h4 className="text-xs font-semibold text-slate-200 truncate mt-0.5">{session.result || 'Erfolgreich abgeschlossen'}</h4>
                      </div>
                      <span className="text-[9px] text-slate-500 whitespace-nowrap mt-0.5">
                        {session.completed_at ? new Date(session.completed_at).toLocaleTimeString() : ''}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Bottom Section: Detaillierte Issue-Liste (Filterbar) */}
      <div className="bg-slate-900/40 rounded-xl border border-slate-800 p-5">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Layers className="w-4 h-4 text-purple-400" />
            <h3 className="text-sm font-bold text-white tracking-wide">
              Themenbasierte Liste ({filteredIssues.length} Aufgaben)
            </h3>
          </div>
          <span className="text-xs text-slate-400 font-medium">Filter: Label "{selectedLabel}"</span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-slate-400 font-semibold bg-slate-950/20">
                <th className="py-2.5 px-3">Nummer</th>
                <th className="py-2.5 px-3">Titel</th>
                <th className="py-2.5 px-3">Status</th>
                <th className="py-2.5 px-3">Erstellt am</th>
                <th className="py-2.5 px-3">Labels</th>
              </tr>
            </thead>
            <tbody>
              {filteredIssues.length === 0 ? (
                <tr>
                  <td colSpan={5} className="py-6 text-center text-slate-500">
                    Keine Issues für diese Filtereinstellung gefunden.
                  </td>
                </tr>
              ) : (
                filteredIssues.map(issue => (
                  <tr key={issue.number} className="border-b border-slate-850 hover:bg-slate-900/20 transition-colors">
                    <td className="py-2.5 px-3 font-semibold text-slate-300">#{issue.number}</td>
                    <td className="py-2.5 px-3 text-slate-200 font-medium">
                      <a href={issue.url} target="_blank" rel="noreferrer" className="hover:text-purple-400 transition-colors">
                        {issue.title}
                      </a>
                    </td>
                    <td className="py-2.5 px-3">
                      <span className={`px-2 py-0.5 rounded-full text-[9px] font-semibold uppercase ${
                        issue.state.toLowerCase() === 'open'
                          ? 'bg-purple-500/20 text-purple-400 border border-purple-500/30'
                          : 'bg-green-500/20 text-green-400 border border-green-500/30'
                      }`}>
                        {issue.state}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-slate-400">
                      {new Date(issue.createdAt).toLocaleDateString()}
                    </td>
                    <td className="py-2.5 px-3 flex flex-wrap gap-1.5 max-w-[300px]">
                      {issue.labels.map(l => (
                        <span
                          key={l.id || l.name}
                          className="px-1.5 py-0.5 rounded text-[8px] font-medium"
                          style={{ backgroundColor: `#${l.color}25`, color: `#${l.color}` }}
                        >
                          {l.name}
                        </span>
                      ))}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
