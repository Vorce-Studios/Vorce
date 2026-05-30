import { useMemo, useState } from 'react';
import { Activity, GitPullRequest, AlertCircle, ExternalLink, CheckCircle, XCircle } from 'lucide-react';
import type { GitHubIssue, ActiveSessions, PullRequest, ActiveDelegation } from '../types';

interface Props {
  issues: GitHubIssue[];
  sessions: ActiveSessions;
  pullRequests: PullRequest[];
}

interface Workstream {
  issue: GitHubIssue;
  session?: ActiveDelegation;
  pr?: PullRequest;
  status: 'COMPLETED' | 'IN_PROGRESS' | 'NEEDS_REVIEW' | 'BLOCKED' | 'ERROR' | 'OPEN';
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

export default function WorkstreamsPage({ issues, sessions, pullRequests }: Props) {
  const [filter, setFilter] = useState<'ALL' | 'ACTIVE' | 'ERROR'>('ALL');

  const workstreams = useMemo(() => {
    return issues.map(issue => {
      // Find matching session
      const session = sessions.active_delegations?.find(s => s.issue_number === issue.number);
      
      // Find matching PR
      let pr = pullRequests.find(p => p.url === session?.pr_url);
      if (!pr) {
        // Fallback: try to find PR by branch name containing issue number
        pr = pullRequests.find(p => p.headRefName.includes(issue.number.toString()));
      }

      // Determine overall status
      let status: Workstream['status'] = 'OPEN';
      
      if (issue.state === 'CLOSED' || (pr && pr.state === 'MERGED')) {
        status = 'COMPLETED';
      } else if (session?.jules_state === 'ESCALATED_TO_USER' || session?.jules_state === 'NEEDS_PLANNING') {
        status = 'ERROR';
      } else if (pr && pr.mergeable === 'CONFLICTING') {
        status = 'ERROR';
      } else if (pr && pr.statusCheckRollup?.some(c => c.conclusion === 'FAILURE')) {
        status = 'ERROR';
      } else if (pr && pr.state === 'OPEN') {
        status = 'NEEDS_REVIEW';
      } else if (session) {
        status = 'IN_PROGRESS';
      }

      return { issue, session, pr, status };
    }).sort((a, b) => {
      // Sort by active / errors first
      const priority = { ERROR: 0, NEEDS_REVIEW: 1, IN_PROGRESS: 2, OPEN: 3, COMPLETED: 4 };
      if (priority[a.status] !== priority[b.status]) {
        return priority[a.status] - priority[b.status];
      }
      return new Date(b.issue.updatedAt).getTime() - new Date(a.issue.updatedAt).getTime();
    });
  }, [issues, sessions, pullRequests]);

  const filteredWorkstreams = useMemo(() => {
    return workstreams.filter(ws => {
      if (filter === 'ACTIVE') return ws.status === 'IN_PROGRESS' || ws.status === 'NEEDS_REVIEW';
      if (filter === 'ERROR') return ws.status === 'ERROR';
      return true;
    });
  }, [workstreams, filter]);

  return (
    <div className="space-y-6 animate-in">
      {/* Header & Filters */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <Activity className="w-5 h-5 text-emerald-400" />
            Smart Workstreams
          </h2>
          <p className="text-sm text-slate-400 mt-1">
            Korrelierte Ansicht von Issues, Agent Sessions und Pull Requests
          </p>
        </div>
        
        <div className="flex gap-2 bg-slate-900/60 p-1.5 rounded-lg border border-slate-800">
          {(['ALL', 'ACTIVE', 'ERROR'] as const).map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all ${
                filter === f
                  ? f === 'ERROR' 
                    ? 'bg-rose-500/20 text-rose-400 border border-rose-500/30'
                    : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {f === 'ALL' ? 'Alle Workstreams' : f === 'ACTIVE' ? 'Aktiv (WIP/PR)' : 'Eskaliert / Fehler'}
            </button>
          ))}
        </div>
      </div>

      {/* Grid of Workstreams */}
      <div className="grid grid-cols-1 gap-4">
        {filteredWorkstreams.length === 0 ? (
          <div className="glass-card p-12 text-center text-slate-400">
            Keine Workstreams gefunden für diesen Filter.
          </div>
        ) : (
          filteredWorkstreams.map((ws) => (
            <div key={ws.issue.number} className="glass-card overflow-hidden hover:border-slate-700 transition-colors">
              {/* Status Bar Top */}
              <div className={`h-1 w-full ${
                ws.status === 'COMPLETED' ? 'bg-slate-700' :
                ws.status === 'ERROR' ? 'bg-rose-500' :
                ws.status === 'NEEDS_REVIEW' ? 'bg-blue-500' :
                ws.status === 'IN_PROGRESS' ? 'bg-emerald-500' : 'bg-slate-800'
              }`} />
              
              <div className="p-5 flex flex-col lg:flex-row gap-6">
                
                {/* Column 1: Issue Context */}
                <div className="flex-1 min-w-[300px]">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="text-xs font-mono text-slate-500">#{ws.issue.number}</span>
                    <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold tracking-wide uppercase ${
                      ws.status === 'COMPLETED' ? 'bg-slate-800 text-slate-400' :
                      ws.status === 'ERROR' ? 'bg-rose-500/20 text-rose-400 border border-rose-500/30' :
                      ws.status === 'NEEDS_REVIEW' ? 'bg-blue-500/20 text-blue-400 border border-blue-500/30' :
                      ws.status === 'IN_PROGRESS' ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' : 
                      'bg-slate-800 text-slate-400'
                    }`}>
                      {ws.status.replace('_', ' ')}
                    </span>
                  </div>
                  <a href={ws.issue.url} target="_blank" rel="noreferrer" className="text-lg font-medium text-slate-200 hover:text-emerald-400 transition-colors flex items-center gap-2 group">
                    {ws.issue.title}
                    <ExternalLink className="w-4 h-4 opacity-0 group-hover:opacity-100 transition-opacity" />
                  </a>
                  
                  <div className="flex flex-wrap gap-1 mt-3">
                    {ws.issue.labels.map(l => (
                      <span key={l.name} className="badge border text-[10px]" style={{
                        borderColor: `#${l.color}40`,
                        backgroundColor: `#${l.color}15`,
                        color: `#${l.color}`
                      }}>
                        {l.name}
                      </span>
                    ))}
                  </div>
                </div>

                {/* Vertical Divider */}
                <div className="hidden lg:block w-px bg-slate-800/60" />

                {/* Column 2: Agent Session */}
                <div className="flex-1 min-w-[200px]">
                  <h3 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3 flex items-center gap-1.5">
                    <Activity className="w-3.5 h-3.5" />
                    Agent Session
                  </h3>
                  {ws.session ? (
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="text-sm text-slate-300">Status:</span>
                        <span className="text-sm font-medium text-purple-400">{ws.session.jules_state}</span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-sm text-slate-400">Retry Count:</span>
                        <span className={`text-sm font-medium ${ws.session.retry_count > 0 ? 'text-rose-400' : 'text-slate-300'}`}>
                          {ws.session.retry_count}
                        </span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-sm text-slate-400">Delegated:</span>
                        <span className="text-xs text-slate-500">{timeAgo(ws.session.delegated_at)}</span>
                      </div>
                    </div>
                  ) : (
                    <div className="flex items-center gap-2 text-slate-500 text-sm italic">
                      <AlertCircle className="w-4 h-4" />
                      Keine aktive Session
                    </div>
                  )}
                </div>

                {/* Vertical Divider */}
                <div className="hidden lg:block w-px bg-slate-800/60" />

                {/* Column 3: Pull Request */}
                <div className="flex-1 min-w-[250px]">
                  <h3 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3 flex items-center gap-1.5">
                    <GitPullRequest className="w-3.5 h-3.5" />
                    Pull Request
                  </h3>
                  {ws.pr ? (
                    <div className="space-y-2">
                      <a href={ws.pr.url} target="_blank" rel="noreferrer" className="text-sm font-medium text-blue-400 hover:text-blue-300 transition-colors flex items-center gap-1.5">
                        #{ws.pr.number} - {ws.pr.headRefName}
                        <ExternalLink className="w-3 h-3" />
                      </a>
                      
                      <div className="flex items-center gap-2 mt-2">
                        {ws.pr.mergeable === 'CONFLICTING' ? (
                          <span className="badge bg-rose-500/20 text-rose-400 border border-rose-500/30 flex items-center gap-1">
                            <XCircle className="w-3 h-3" />
                            Merge Conflict
                          </span>
                        ) : ws.pr.mergeable === 'MERGEABLE' ? (
                          <span className="badge bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center gap-1">
                            <CheckCircle className="w-3 h-3" />
                            Clean
                          </span>
                        ) : (
                          <span className="badge bg-slate-800 text-slate-400">
                            {ws.pr.mergeable}
                          </span>
                        )}
                      </div>

                      {/* CI Checks Preview */}
                      {ws.pr.statusCheckRollup && ws.pr.statusCheckRollup.length > 0 && (
                        <div className="mt-3 flex flex-wrap gap-1">
                          {ws.pr.statusCheckRollup.map((check, idx) => (
                            <div key={idx} className={`w-2 h-2 rounded-full ${
                              check.conclusion === 'SUCCESS' ? 'bg-emerald-500' :
                              check.conclusion === 'FAILURE' ? 'bg-rose-500' :
                              'bg-amber-400 animate-pulse'
                            }`} title={`${check.name || check.context}: ${check.conclusion || check.state}`} />
                          ))}
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="flex items-center gap-2 text-slate-500 text-sm italic">
                      <GitPullRequest className="w-4 h-4 opacity-50" />
                      Noch kein PR erstellt
                    </div>
                  )}
                </div>

              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
