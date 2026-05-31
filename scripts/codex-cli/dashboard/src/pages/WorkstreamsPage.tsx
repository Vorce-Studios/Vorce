import { useMemo, useState } from 'react';
import { Activity, GitPullRequest, AlertCircle, CheckCircle, XCircle, ChevronRight, ChevronDown, Layers, Filter, Search } from 'lucide-react';
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
  status: 'COMPLETED' | 'IN_PROGRESS' | 'NEEDS_REVIEW' | 'BLOCKED' | 'ERROR' | 'OPEN' | 'CONFLICTING' | 'STALLED';
  sortScore: number;
  isMaster: boolean;
  parentId?: string;
  children: Workstream[];
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

function getStatusColor(status: Workstream['status']) {
  switch (status) {
    case 'ERROR': return { border: '#f43f5e', bg: 'bg-rose-500/20', text: 'text-rose-400', borderClass: 'border-rose-500/30' };
    case 'CONFLICTING': return { border: '#e11d48', bg: 'bg-rose-600/35', text: 'text-rose-300 font-bold', borderClass: 'border-rose-500/50 animate-pulse' };
    case 'STALLED': return { border: '#d97706', bg: 'bg-amber-600/20', text: 'text-amber-300 font-semibold', borderClass: 'border-amber-500/40' };
    case 'NEEDS_REVIEW': return { border: '#3b82f6', bg: 'bg-blue-500/20', text: 'text-blue-400', borderClass: 'border-blue-500/30' };
    case 'IN_PROGRESS': return { border: '#10b981', bg: 'bg-emerald-500/20', text: 'text-emerald-400', borderClass: 'border-emerald-500/30' };
    case 'COMPLETED': return { border: '#334155', bg: 'bg-slate-700/20', text: 'text-slate-400', borderClass: 'border-slate-700/30' };
    case 'BLOCKED': return { border: '#f97316', bg: 'bg-orange-500/20', text: 'text-orange-400', borderClass: 'border-orange-500/30' };
    case 'OPEN': default: return { border: '#475569', bg: 'bg-slate-700/20', text: 'text-slate-300', borderClass: 'border-slate-700/30' };
  }
}

function fixGithubUrl(url: string | undefined): string {
  if (!url) return '';
  return url.replace(/github\.com\/[^\/]+\/MapFlow/gi, 'github.com/Vorce-Studios/Vorce');
}

export default function WorkstreamsPage({ issues, sessions, pullRequests, julesSessions }: Props) {
  const [filter, setFilter] = useState<'ALL' | 'ACTIVE' | 'ERROR'>('ALL');
  const [isGrouped, setIsGrouped] = useState(true);
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());
  const [expandedDetails, setExpandedDetails] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'PRIORITY' | 'RECENT' | 'NUMBER'>('PRIORITY');

  const toggleGroup = (id: string) => {
    const newSet = new Set(expandedGroups);
    if (newSet.has(id)) newSet.delete(id);
    else newSet.add(id);
    setExpandedGroups(newSet);
  };

  const toggleDetails = (id: string) => {
    const newSet = new Set(expandedDetails);
    if (newSet.has(id)) newSet.delete(id);
    else newSet.add(id);
    setExpandedDetails(newSet);
  };

  const workstreams = useMemo(() => {
    const wsMap = new Map<string, Workstream>();

    const getOrAdd = (id: string): Workstream => {
      if (!wsMap.has(id)) {
        wsMap.set(id, { id, status: 'OPEN', sortScore: 0, isMaster: false, children: [] });
      }
      return wsMap.get(id)!;
    };

    // 1. Alle relevanten Issues einfügen
    issues.forEach(issue => {
      const isRelevant = issue.state === 'OPEN' || issue.labels.some(l => l.name === 'jules-task' || l.name.startsWith('bug'));
      if (isRelevant || issue.state === 'OPEN') {
        const ws = getOrAdd(issue.number.toString());
        ws.issue = issue;
        if (issue.title.includes('_MAIs_') || issue.title.includes('_StIs_') || issue.title.includes('Master-Issue') || issue.title.includes('[MASTER]')) {
          ws.isMaster = true;
        }
      }
    });

    // 2. Aktive Delegations
    sessions.active_delegations?.forEach(del => {
      const ws = getOrAdd(del.issue_number.toString());
      ws.session = del;
    });

    // 3. Jules Sessions (Raw) Fallback mit repariertem Mapping
    julesSessions?.forEach(js => {
      if (!js.repo.includes('Vorce')) return;
      if (js.state === 'COMPLETED' || js.state === 'QUEUED') return;

      let issueNum = '';
      if (js.issueNumber) {
        issueNum = js.issueNumber.toString();
      } else {
        const match = js.title?.match(/#(\d+)/);
        if (match) issueNum = match[1];
      }

      const targetId = issueNum || `session_${js.name?.split('/')?.[1] || js.name}`;
      const ws = getOrAdd(targetId);
      ws.julesSessionRaw = js;
    });

    // 4. Open PRs
    pullRequests.forEach(pr => {
      if (pr.state === 'CLOSED') return;

      let targetId = '';
      const match = pr.headRefName.match(/(\d+)/);
      if (match) {
        targetId = match[1];
      } else {
        targetId = `pr_${pr.number}`;
      }

      const ws = getOrAdd(targetId);
      ws.pr = pr;
    });

    // 5. Status & Parent-Child Verknüpfung
    const allWs = Array.from(wsMap.values());

    allWs.forEach(ws => {
      let status: Workstream['status'] = 'OPEN';
      let sortScore = 0;

      const isConflicting = ws.pr && ws.pr.mergeable === 'CONFLICTING';
      const hasFailedChecks = ws.pr && ws.pr.statusCheckRollup?.some(c => c.conclusion === 'FAILURE');
      const hasSessionError = ws.session?.jules_state === 'FAILED' || ws.julesSessionRaw?.state === 'FAILED';

      const isStalled = ws.session?.jules_state === 'AWAITING_USER_FEEDBACK' ||
                        ws.session?.jules_state === 'ESCALATED_TO_USER' ||
                        ws.julesSessionRaw?.state === 'AWAITING_USER_FEEDBACK' ||
                        ws.julesSessionRaw?.state === 'AWAITING_USER_FEEDBACK_CI_OR_BLOCKER';

      const isBlocked = ws.issue?.labels?.some(l => l.name === 'status: blocked');
      const needsReview = ws.issue?.labels?.some(l => l.name === 'status: needs-review' || l.name === 'status: needs-testing');

      if (isConflicting) {
        status = 'CONFLICTING';
        sortScore = 1100;
      } else if (hasFailedChecks || hasSessionError) {
        status = 'ERROR';
        sortScore = 1000;
      } else if (isStalled) {
        status = 'STALLED';
        sortScore = 980;
      } else if (isBlocked) {
        status = 'BLOCKED';
        sortScore = 950;
      } else if (ws.issue?.state === 'CLOSED' || (ws.pr && ws.pr.state === 'MERGED')) {
        status = 'COMPLETED';
        sortScore = -100;
      } else if (needsReview || (ws.pr && ws.pr.state === 'OPEN')) {
        status = 'NEEDS_REVIEW';
        sortScore = 800;
      } else if (ws.session || ws.julesSessionRaw || ws.issue?.labels?.some(l => l.name === 'status: in-progress')) {
        status = 'IN_PROGRESS';
        sortScore = 900;
      }

      ws.status = status;

      const dateStr = ws.pr?.updatedAt || ws.session?.last_checked_at || ws.issue?.updatedAt || '';
      if (dateStr) {
        sortScore += new Date(dateStr).getTime() / 100000000000;
      }
      ws.sortScore = sortScore;

      // Finde Parent für Sub-Issues
      if (!ws.isMaster && ws.issue?.body) {
        const regex = /#(\d+)/g;
        let match;
        while ((match = regex.exec(ws.issue.body)) !== null) {
          const possibleParentId = match[1];
          const potentialParent = wsMap.get(possibleParentId);
          if (potentialParent && potentialParent.isMaster && possibleParentId !== ws.id) {
            ws.parentId = possibleParentId;
            break;
          }
        }
      }
    });

    // 6. Hierarchy aufbauen
    const roots: Workstream[] = [];
    allWs.forEach(ws => {
      if (ws.parentId && wsMap.has(ws.parentId)) {
        wsMap.get(ws.parentId)!.children.push(ws);
      } else {
        roots.push(ws);
      }
    });

    // Master erbt den höchsten Status-Schweregrad seiner Kinder
    allWs.forEach(ws => {
      if (ws.isMaster && ws.children.length > 0) {
        const childStatuses = ws.children.map(c => c.status);
        if (childStatuses.includes('ERROR')) {
          ws.status = 'ERROR';
          ws.sortScore = Math.max(ws.sortScore, 1000);
        } else if (childStatuses.includes('CONFLICTING')) {
          ws.status = 'CONFLICTING';
          ws.sortScore = Math.max(ws.sortScore, 1100);
        } else if (childStatuses.includes('STALLED')) {
          ws.status = 'STALLED';
          ws.sortScore = Math.max(ws.sortScore, 980);
        } else if (childStatuses.includes('IN_PROGRESS')) {
          ws.status = 'IN_PROGRESS';
          ws.sortScore = Math.max(ws.sortScore, 900);
        } else if (childStatuses.includes('NEEDS_REVIEW')) {
          ws.status = 'NEEDS_REVIEW';
          ws.sortScore = Math.max(ws.sortScore, 800);
        } else if (childStatuses.includes('BLOCKED')) {
          ws.status = 'BLOCKED';
          ws.sortScore = Math.max(ws.sortScore, 950);
        } else if (childStatuses.includes('OPEN')) {
          ws.status = 'OPEN';
          ws.sortScore = Math.max(ws.sortScore, 0);
        } else {
          ws.status = 'COMPLETED';
          ws.sortScore = Math.max(ws.sortScore, -100);
        }
      }
    });

    return roots.sort((a, b) => b.sortScore - a.sortScore);
  }, [issues, sessions, pullRequests, julesSessions]);

  const filteredWorkstreams = useMemo(() => {
    let result = workstreams;

    if (!isGrouped) {
      const flatten = (wsList: Workstream[]): Workstream[] => {
        let flat: Workstream[] = [];
        wsList.forEach(ws => {
          flat.push(ws);
          if (ws.children.length > 0) flat = flat.concat(flatten(ws.children));
        });
        return flat;
      };
      result = flatten(workstreams);
    }

    // Filter und Suche anwenden
    let filtered = result.filter(ws => {
      // 1. Suche nach Titel / Nummer
      if (searchQuery) {
        const query = searchQuery.toLowerCase();
        const matchesIssue = ws.issue && (ws.issue.title.toLowerCase().includes(query) || ws.issue.number.toString().includes(query));
        const matchesPr = ws.pr && (ws.pr.title.toLowerCase().includes(query) || ws.pr.number.toString().includes(query));
        const matchesSession = ws.session && ws.session.jules_session_id.toLowerCase().includes(query);
        const matchesChildren = ws.children.some(c =>
          c.issue?.title.toLowerCase().includes(query) ||
          c.issue?.number.toString().includes(query)
        );
        if (!matchesIssue && !matchesPr && !matchesSession && !matchesChildren) {
          return false;
        }
      }

      // 2. Status-Filter
      if (filter === 'ACTIVE') {
        return ws.status === 'IN_PROGRESS' ||
               ws.status === 'NEEDS_REVIEW' ||
               ws.status === 'ERROR' ||
               ws.status === 'CONFLICTING' ||
               ws.status === 'STALLED' ||
               ws.children.some(c => c.status === 'IN_PROGRESS' || c.status === 'NEEDS_REVIEW' || c.status === 'CONFLICTING' || c.status === 'STALLED');
      }
      if (filter === 'ERROR') {
        return ws.status === 'ERROR' ||
               ws.status === 'CONFLICTING' ||
               ws.children.some(c => c.status === 'ERROR' || c.status === 'CONFLICTING');
      }
      return true;
    });

    // Sortierung anwenden
    return [...filtered].sort((a, b) => {
      if (sortBy === 'RECENT') {
        const dateA = new Date(a.pr?.updatedAt || a.session?.last_checked_at || a.issue?.updatedAt || 0).getTime();
        const dateB = new Date(b.pr?.updatedAt || b.session?.last_checked_at || b.issue?.updatedAt || 0).getTime();
        return dateB - dateA;
      }
      if (sortBy === 'NUMBER') {
        const numA = a.issue?.number || 0;
        const numB = b.issue?.number || 0;
        return numA - numB;
      }
      return b.sortScore - a.sortScore;
    });
  }, [workstreams, filter, isGrouped, searchQuery, sortBy]);

  const expandAllDetails = () => {
    const allIds = new Set<string>();
    const collect = (list: Workstream[]) => {
      list.forEach(ws => {
        allIds.add(ws.id);
        if (ws.children.length > 0) collect(ws.children);
      });
    };
    collect(workstreams);
    setExpandedDetails(allIds);
  };

  const collapseAllDetails = () => {
    setExpandedDetails(new Set());
  };

  const renderWorkstream = (ws: Workstream, isChild = false) => {
    const isExpanded = expandedGroups.has(ws.id);
    const isDetailExpanded = expandedDetails.has(ws.id);
    const hasChildren = ws.children.length > 0;
    const colors = getStatusColor(ws.status);

    const issueUrl = ws.issue ? fixGithubUrl(ws.issue.url) : '';
    const sessionPrUrl = ws.session?.pr_url ? fixGithubUrl(ws.session.pr_url) : '';
    const prUrl = ws.pr ? fixGithubUrl(ws.pr.url) : '';

    return (
      <div key={ws.id} className="flex flex-col">
        <div
          className={`glass-card overflow-hidden hover:border-slate-700 transition-colors flex flex-col border-l-4 ${isChild ? 'ml-8 my-1 opacity-90 scale-[0.98]' : 'mb-3'}`}
          style={{ borderLeftColor: colors.border }}
        >
          {/* COMPACT MINIMAL BAR */}
          <div className="flex flex-wrap items-center justify-between p-3 gap-3">
            <div className="flex items-center gap-3 min-w-0 flex-1">
              {hasChildren && isGrouped && (
                <button onClick={() => toggleGroup(ws.id)} className="p-1 hover:bg-slate-800 rounded text-slate-400 flex-shrink-0">
                  {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                </button>
              )}
              {ws.isMaster ? <Layers className="w-4 h-4 text-purple-400 flex-shrink-0" /> : <AlertCircle className="w-4 h-4 text-slate-500 flex-shrink-0" />}
              <span className={`badge ${colors.bg} ${colors.text} border ${colors.borderClass} text-[10px] flex-shrink-0`}>
                {ws.status}
              </span>

              {ws.issue ? (
                <a href={issueUrl} target="_blank" rel="noreferrer" className="text-sm font-medium text-slate-200 hover:text-emerald-400 transition-colors truncate" title={ws.issue.title}>
                  <span className="text-slate-500 font-mono mr-1.5">#{ws.issue.number}</span>
                  {ws.issue.title}
                </a>
              ) : (
                <span className="text-sm text-slate-400 italic truncate">Kein lokales Issue gefunden (ID: {ws.id})</span>
              )}
            </div>

            <div className="flex items-center gap-2 flex-shrink-0">
              {/* Quick Session Indicator */}
              {ws.session ? (
                <span className="text-xs bg-emerald-500/10 text-emerald-400 px-2 py-1 rounded border border-emerald-500/20 font-medium">
                  {ws.session.agent_type || 'Jules'} ({ws.session.jules_state})
                </span>
              ) : ws.julesSessionRaw ? (
                <span className="text-xs bg-emerald-500/10 text-emerald-400 px-2 py-1 rounded border border-emerald-500/20 font-medium">
                  Jules ({ws.julesSessionRaw.state})
                </span>
              ) : null}

              {/* Quick PR Indicator */}
              {ws.pr && (
                <a href={prUrl} target="_blank" rel="noreferrer" className={`text-xs px-2 py-1 rounded border font-medium flex items-center gap-1 hover:underline ${
                  ws.pr.mergeable === 'CONFLICTING' ? 'bg-rose-500/10 text-rose-400 border-rose-500/20' : 'bg-blue-500/10 text-blue-400 border-blue-500/20'
                }`}>
                  PR #{ws.pr.number} ({ws.pr.mergeable})
                </a>
              )}

              {/* Last checked / updated */}
              <span className="text-[11px] text-slate-500 hidden sm:inline">
                {timeAgo(ws.pr?.updatedAt || ws.session?.last_checked_at || ws.issue?.updatedAt || '')}
              </span>

              {/* Toggle Details Button */}
              <button
                onClick={() => toggleDetails(ws.id)}
                className="px-2 py-1 text-[11px] font-medium rounded bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition-colors"
              >
                {isDetailExpanded ? 'Details zuklappen' : 'Details aufklappen'}
              </button>
            </div>
          </div>

          {/* DETAIL VIEW */}
          {isDetailExpanded && (
            <div className="border-t border-slate-800/80 flex flex-col md:flex-row divide-y md:divide-y-0 md:divide-x divide-slate-850 bg-slate-900/15">
              {/* Issue Box Details */}
              <div className="flex-1 p-4 flex flex-col min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">
                    {ws.isMaster ? 'Master Issue Details' : 'Issue Details'}
                  </span>
                </div>
                {ws.issue ? (
                  <div className="mt-1">
                    <p className="text-xs text-slate-400 line-clamp-3 mb-2">{ws.issue.body || 'Keine Beschreibung vorhanden.'}</p>
                    <div className="flex flex-wrap gap-1">
                      {ws.issue.labels.map(l => (
                        <span key={l.name} className="px-1.5 py-0.5 rounded text-[10px] bg-slate-800 text-slate-300 border border-slate-700">
                          {l.name}
                        </span>
                      ))}
                    </div>
                  </div>
                ) : (
                  <div className="mt-1 text-sm text-slate-500 italic">Keine Issue Details.</div>
                )}
              </div>

              {/* Agent Session Details */}
              <div className="flex-1 p-4 bg-slate-900/30 flex flex-col min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <Activity className={`w-4 h-4 flex-shrink-0 ${(ws.session || ws.julesSessionRaw) ? 'text-emerald-500' : 'text-slate-600'}`} />
                  <span className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Agent Session</span>
                  {(ws.session || ws.julesSessionRaw) && (
                    <span className="ml-auto text-[10px] text-slate-500 font-mono">
                      {timeAgo(ws.session?.last_checked_at || ws.julesSessionRaw?.updated_at)}
                    </span>
                  )}
                </div>
                {ws.session ? (
                  <div>
                    <div className="text-sm font-medium text-emerald-400 truncate" title={ws.session.jules_session_id}>
                      {ws.session.agent_type || 'Jules'} &bull; {ws.session.jules_state}
                    </div>
                    {ws.session.retry_count > 0 && (
                      <div className="text-xs text-rose-400 mt-1">Retries: {ws.session.retry_count}</div>
                    )}
                    {sessionPrUrl && (
                      <a href={sessionPrUrl} target="_blank" rel="noreferrer" className="text-xs text-blue-400 hover:underline mt-1 block truncate">
                        {sessionPrUrl}
                      </a>
                    )}
                  </div>
                ) : ws.julesSessionRaw ? (
                  <div>
                    <div className="text-sm font-medium text-emerald-400 truncate" title={ws.julesSessionRaw.name}>
                      Jules &bull; {ws.julesSessionRaw.state}
                    </div>
                    <div className="text-xs text-slate-500 mt-1 truncate">
                      ID: {ws.julesSessionRaw.name?.split('/')?.[1] || ws.julesSessionRaw.name}
                    </div>
                    {ws.julesSessionRaw.url && (
                      <a href={fixGithubUrl(ws.julesSessionRaw.url)} target="_blank" rel="noreferrer" className="text-xs text-blue-400 hover:underline mt-1 block truncate">
                        Jules Console
                      </a>
                    )}
                  </div>
                ) : (
                  <div className="text-sm text-slate-600 italic">Kein Agent aktiv</div>
                )}
              </div>

              {/* Pull Request Box Details */}
              <div className="flex-1 p-4 bg-slate-900/30 flex flex-col min-w-0">
                <div className="flex items-center gap-2 mb-2">
                  <GitPullRequest className={`w-4 h-4 flex-shrink-0 ${ws.pr ? 'text-blue-400' : 'text-slate-600'}`} />
                  <span className="text-[11px] font-semibold uppercase tracking-wider text-slate-400">Pull Request</span>
                </div>
                {ws.pr ? (
                  <div>
                    <a href={prUrl} target="_blank" rel="noreferrer" className="text-sm font-medium text-slate-200 hover:text-blue-400 transition-colors line-clamp-1" title={ws.pr.title}>
                      #{ws.pr.number} {ws.pr.title}
                    </a>
                    <div className="flex items-center gap-3 mt-2">
                      <span className={`text-[10px] px-1.5 py-0.5 rounded border ${
                        ws.pr.mergeable === 'CONFLICTING' ? 'bg-rose-500/20 text-rose-400 border-rose-500/30' :
                        ws.pr.mergeable === 'MERGEABLE' ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30' :
                        'bg-slate-800 text-slate-400 border-slate-700'
                      }`}>
                        {ws.pr.mergeable}
                      </span>
                      {ws.pr.statusCheckRollup?.length > 0 && (
                        <div className="flex -space-x-1">
                          {ws.pr.statusCheckRollup.slice(0, 5).map((check, i) => (
                            <div key={i} className="w-4 h-4 rounded-full bg-slate-800 border border-slate-700 flex items-center justify-center" title={check.context || check.name}>
                              {check.conclusion === 'SUCCESS' ? <CheckCircle className="w-3 h-3 text-emerald-500" /> :
                               check.conclusion === 'FAILURE' ? <XCircle className="w-3 h-3 text-rose-500" /> :
                               <div className="w-1.5 h-1.5 rounded-full bg-slate-500" />}
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="text-sm text-slate-600 italic">Kein PR vorhanden</div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Children Rendering */}
        {hasChildren && isGrouped && isExpanded && (
          <div className="flex flex-col border-l-2 border-slate-800 ml-6 pl-4 border-dashed">
            {ws.children.map(child => renderWorkstream(child, true))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="space-y-6 animate-in">
      {/* Header & Filters */}
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 bg-slate-900/40 p-4 rounded-xl border border-slate-800/60 backdrop-blur-sm">
        <div>
          <h2 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <Activity className="w-5 h-5 text-emerald-400" />
            Smart Workstreams
          </h2>
          <p className="text-sm text-slate-400 mt-1">
            Korrelierte Ansicht von Issues, Agent Sessions und Pull Requests
          </p>
        </div>

        <div className="flex flex-col sm:flex-row gap-3 w-full lg:w-auto">
          {/* Suche */}
          <div className="relative flex-1 sm:w-60">
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-slate-500" />
            <input
              type="text"
              placeholder="Suchen nach Titel oder Nr..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9 pr-4 py-2 w-full text-sm bg-slate-950/80 border border-slate-700/60 rounded-lg text-slate-200 placeholder-slate-500 focus:outline-none focus:border-emerald-500/50"
            />
          </div>

          {/* Details Expand/Collapse */}
          <div className="flex bg-slate-900/80 p-1 rounded-lg border border-slate-700/50 flex-shrink-0">
            <button
              onClick={expandAllDetails}
              className="px-2.5 py-1.5 text-xs font-medium rounded text-slate-400 hover:text-slate-200 transition-colors"
              title="Alle Details aufklappen"
            >
              Alle Details auf
            </button>
            <button
              onClick={collapseAllDetails}
              className="px-2.5 py-1.5 text-xs font-medium rounded text-slate-400 hover:text-slate-200 transition-colors"
              title="Alle Details zuklappen"
            >
              Alle Details zu
            </button>
          </div>

          {/* Gruppierung */}
          <div className="flex items-center bg-slate-900/80 p-1 rounded-lg border border-slate-700/50 flex-shrink-0">
            <button
              onClick={() => setIsGrouped(true)}
              className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all flex items-center gap-1.5 ${
                isGrouped ? 'bg-slate-700/50 text-slate-200 shadow-sm' : 'text-slate-400 hover:text-slate-300'
              }`}
            >
              <Layers className="w-3.5 h-3.5" />
              Grouped
            </button>
            <button
              onClick={() => setIsGrouped(false)}
              className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all flex items-center gap-1.5 ${
                !isGrouped ? 'bg-slate-700/50 text-slate-200 shadow-sm' : 'text-slate-400 hover:text-slate-300'
              }`}
            >
              <Filter className="w-3.5 h-3.5" />
              Flat List
            </button>
          </div>

          {/* Sortierung */}
          <div className="flex items-center bg-slate-900/80 p-1 rounded-lg border border-slate-700/50 flex-shrink-0">
            <select
              value={sortBy}
              onChange={(e: any) => setSortBy(e.target.value)}
              className="bg-transparent text-xs text-slate-300 focus:outline-none px-2 py-1 font-medium cursor-pointer"
            >
              <option value="PRIORITY" className="bg-slate-900 text-slate-300">Sort: Priorität</option>
              <option value="RECENT" className="bg-slate-900 text-slate-300">Sort: Zuletzt geändert</option>
              <option value="NUMBER" className="bg-slate-900 text-slate-300">Sort: Issue-Nummer</option>
            </select>
          </div>

          {/* Status-Filter */}
          <div className="flex gap-1 bg-slate-900/80 p-1 rounded-lg border border-slate-700/50 flex-shrink-0">
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
                {f === 'ALL' ? 'Alle' : f === 'ACTIVE' ? 'Aktiv' : 'Fehler'}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Pipeline View */}
      <div className="space-y-1">
        {filteredWorkstreams.length === 0 ? (
          <div className="glass-card p-12 text-center text-slate-400 border-dashed border-slate-800">
            Keine Workstreams gefunden für diesen Filter.
          </div>
        ) : (
          filteredWorkstreams.map(ws => renderWorkstream(ws))
        )}
      </div>
    </div>
  );
}
