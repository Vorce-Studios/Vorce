import { useMemo, useState } from 'react';
import { Activity, GitPullRequest, AlertCircle, ExternalLink, CheckCircle, XCircle } from 'lucide-react';
import type { GitHubIssue, ActiveSessions, PullRequest, ActiveDelegation } from '../types';

interface Props {
  issues: GitHubIssue[];
  sessions: ActiveSessions;
  pullRequests: PullRequest[];
  julesSessions?: any[];
}

interface Workstream {
  id: string; // Issue number or PR number or Session ID
  issue?: GitHubIssue;
  session?: ActiveDelegation;
  julesSessionRaw?: any; // Aus julesSessions array falls keine Delegation
  pr?: PullRequest;
  status: 'COMPLETED' | 'IN_PROGRESS' | 'NEEDS_REVIEW' | 'BLOCKED' | 'ERROR' | 'OPEN';
  sortScore: number;
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

export default function WorkstreamsPage({ issues, sessions, pullRequests, julesSessions }: Props) {
  const [filter, setFilter] = useState<'ALL' | 'ACTIVE' | 'ERROR'>('ALL');

  const workstreams = useMemo(() => {
    const wsMap = new Map<string, Workstream>();

    // Helper zum Einfügen/Updaten
    const getOrAdd = (id: string): Workstream => {
      if (!wsMap.has(id)) {
        wsMap.set(id, { id, status: 'OPEN', sortScore: 0 });
      }
      return wsMap.get(id)!;
    };

    // 1. Alle relevanten Issues einfügen
    issues.forEach(issue => {
      const isRelevant = issue.state === 'OPEN' || issue.labels.some(l => l.name === 'jules-task' || l.name.startsWith('bug'));
      if (isRelevant || issue.state === 'OPEN') {
        const ws = getOrAdd(issue.number.toString());
        ws.issue = issue;
      }
    });

    // 2. Aktive Delegations aus sessions.json
    sessions.active_delegations?.forEach(del => {
      const ws = getOrAdd(del.issue_number.toString());
      ws.session = del;
    });

    // 3. Jules Sessions (Raw) aus jules-sessions.json als Fallback
    julesSessions?.forEach(js => {
      if (!js.repo.includes('Vorce')) return;
      if (js.state === 'COMPLETED' || js.state === 'QUEUED') return;
      
      // Versuche Issue-Number aus Title zu extrahieren "MF-StIs_IssueTitle #123"
      let issueNum = '';
      const match = js.issue_title?.match(/#(\d+)/);
      if (match) issueNum = match[1];
      
      const targetId = issueNum || `session_${js.id}`;
      const ws = getOrAdd(targetId);
      ws.julesSessionRaw = js;
    });

    // 4. Open PRs
    pullRequests.forEach(pr => {
      if (pr.state === 'CLOSED') return; // Ignore closed without merge
      
      // Finde verknüpftes Issue
      let targetId = '';
      const match = pr.headRefName.match(/(\d+)/); // z.B. feature/123-foo
      if (match) {
        targetId = match[1];
      } else {
        targetId = `pr_${pr.number}`;
      }

      const ws = getOrAdd(targetId);
      ws.pr = pr;
    });

    // 5. Status evaluieren & sortieren
    return Array.from(wsMap.values()).map(ws => {
      let status: Workstream['status'] = 'OPEN';
      let sortScore = 0;

      const hasPrError = ws.pr && (ws.pr.mergeable === 'CONFLICTING' || ws.pr.statusCheckRollup?.some(c => c.conclusion === 'FAILURE'));
      const hasSessionError = ws.session?.jules_state === 'ESCALATED_TO_USER' || ws.session?.jules_state === 'FAILED';
      const hasRawSessionError = ws.julesSessionRaw?.state === 'FAILED';

      if (hasPrError || hasSessionError || hasRawSessionError) {
        status = 'ERROR';
        sortScore = 1000;
      } else if (ws.issue?.state === 'CLOSED' || (ws.pr && ws.pr.state === 'MERGED')) {
        status = 'COMPLETED';
        sortScore = -100;
      } else if (ws.pr && ws.pr.state === 'OPEN') {
        status = 'NEEDS_REVIEW';
        sortScore = 800;
      } else if (ws.session || ws.julesSessionRaw) {
        status = 'IN_PROGRESS';
        sortScore = 900;
      }

      ws.status = status;
      
      // Fallback-Score basierend auf Datum (neueste zuerst)
      const dateStr = ws.pr?.updatedAt || ws.session?.last_checked_at || ws.issue?.updatedAt || '';
      if (dateStr) {
        sortScore += new Date(dateStr).getTime() / 100000000000;
      }

      return ws;
    }).sort((a, b) => b.sortScore - a.sortScore);
  }, [issues, sessions, pullRequests, julesSessions]);

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

      {/* Pipeline View */}
      <div className="space-y-3">
        {filteredWorkstreams.length === 0 ? (
          <div className="glass-card p-12 text-center text-slate-400">
            Keine Workstreams gefunden für diesen Filter.
          </div>
        ) : (
          filteredWorkstreams.map((ws) => (
            <div key={ws.id} className="glass-card overflow-hidden hover:border-slate-700 transition-colors flex flex-col md:flex-row border-l-4" style={{
              borderLeftColor: ws.status === 'ERROR' ? '#f43f5e' : ws.status === 'COMPLETED' ? '#334155' : ws.status === 'NEEDS_REVIEW' ? '#3b82f6' : ws.status === 'IN_PROGRESS' ? '#10b981' : '#475569'
            }}>
              
              {/* 1. Issue Box */}
              <div className="flex-1 p-4 md:border-r border-slate-800 flex flex-col min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <AlertCircle className="w-4 h-4 text-slate-500 flex-shrink-0" />
                  <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Context</span>
                  {ws.status === 'ERROR' && <span className="ml-auto badge bg-rose-500/20 text-rose-400 border border-rose-500/30 text-[10px]">ERROR</span>}
                  {ws.status === 'NEEDS_REVIEW' && <span className="ml-auto badge bg-blue-500/20 text-blue-400 border border-blue-500/30 text-[10px]">REVIEW</span>}
                </div>
                {ws.issue ? (
                  <div className="mt-1">
                    <a href={ws.issue.url} target="_blank" rel="noreferrer" className="text-sm font-medium text-slate-200 hover:text-emerald-400 transition-colors line-clamp-2" title={ws.issue.title}>
                      <span className="text-slate-500 font-mono mr-1.5">#{ws.issue.number}</span>
                      {ws.issue.title}
                    </a>
                    <div className="flex flex-wrap gap-1 mt-2">
                      {ws.issue.labels.slice(0, 3).map(l => (
                        <span key={l.name} className="badge border text-[10px] py-0 px-1" style={{ borderColor: `#${l.color}40`, color: `#${l.color}` }}>
                          {l.name}
                        </span>
                      ))}
                      {ws.issue.labels.length > 3 && <span className="text-xs text-slate-500">+{ws.issue.labels.length - 3}</span>}
                    </div>
                  </div>
                ) : (
                  <div className="text-sm text-slate-500 italic mt-1">Kein verknüpftes Issue</div>
                )}
              </div>

              {/* 2. Agent Box */}
              <div className="flex-1 p-4 md:border-r border-slate-800 flex flex-col min-w-0 bg-slate-900/30">
                <div className="flex items-center gap-2 mb-2">
                  <Activity className="w-4 h-4 text-purple-500 flex-shrink-0" />
                  <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Agent Task</span>
                </div>
                {ws.session ? (
                  <div className="mt-1 space-y-1.5">
                    <div className="flex items-center gap-2">
                      <span className={`text-sm font-medium ${ws.session.jules_state.includes('FAILED') || ws.session.jules_state.includes('ESCALATED') ? 'text-rose-400' : 'text-purple-400'}`}>
                        {ws.session.jules_state.replace(/_/g, ' ')}
                      </span>
                    </div>
                    <div className="text-xs text-slate-500 flex items-center gap-2">
                      <span>Retries: <span className={ws.session.retry_count > 0 ? 'text-rose-400' : ''}>{ws.session.retry_count}</span></span>
                      <span>•</span>
                      <span>{timeAgo(ws.session.last_checked_at)}</span>
                    </div>
                  </div>
                ) : ws.julesSessionRaw ? (
                  <div className="mt-1 space-y-1.5">
                    <div className="flex items-center gap-2">
                      <span className={`text-sm font-medium text-purple-400`}>
                        {ws.julesSessionRaw.state}
                      </span>
                    </div>
                    <div className="text-xs text-slate-500">
                      ID: {ws.julesSessionRaw.id}
                    </div>
                  </div>
                ) : (
                  <div className="text-sm text-slate-500 italic mt-1">Keine aktive Task</div>
                )}
              </div>

              {/* 3. PR Box */}
              <div className="flex-1 p-4 flex flex-col min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <GitPullRequest className="w-4 h-4 text-cyan-500 flex-shrink-0" />
                  <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">Pull Request</span>
                </div>
                {ws.pr ? (
                  <div className="mt-1 space-y-2">
                    <a href={ws.pr.url} target="_blank" rel="noreferrer" className="text-sm font-medium text-blue-400 hover:text-blue-300 transition-colors flex items-center gap-1.5 line-clamp-1" title={ws.pr.headRefName}>
                      #{ws.pr.number} {ws.pr.headRefName}
                    </a>
                    
                    <div className="flex items-center gap-2">
                      {ws.pr.mergeable === 'CONFLICTING' ? (
                        <span className="badge bg-rose-500/20 text-rose-400 border border-rose-500/30 text-[10px] py-0"><XCircle className="w-3 h-3 mr-1 inline"/> Conflict</span>
                      ) : ws.pr.mergeable === 'MERGEABLE' ? (
                        <span className="badge bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 text-[10px] py-0"><CheckCircle className="w-3 h-3 mr-1 inline"/> Clean</span>
                      ) : (
                        <span className="badge bg-slate-800 text-slate-400 text-[10px] py-0">{ws.pr.mergeable}</span>
                      )}
                    </div>

                    {ws.pr.statusCheckRollup && ws.pr.statusCheckRollup.length > 0 && (
                      <div className="flex flex-wrap gap-1 pt-1">
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
                  <div className="text-sm text-slate-500 italic mt-1">Kein PR erstellt</div>
                )}
              </div>

            </div>
          ))
        )}
      </div>
    </div>
  );
}
