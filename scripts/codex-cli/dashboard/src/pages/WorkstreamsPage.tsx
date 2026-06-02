import { useMemo, useState } from 'react';
import { Activity, GitPullRequest, AlertCircle, CheckCircle, XCircle, ChevronRight, ChevronDown, Layers, Filter, Search } from 'lucide-react';
import type { GitHubIssue, ActiveSessions, PullRequest, ActiveDelegation } from '../types';

interface Props {
  issues: GitHubIssue[];
  sessions: ActiveSessions;
  pullRequests: PullRequest[];
  julesSessions?: any[];
  projectItems?: any[];
}

interface Workstream {
  id: string; // Issue number or PR number or Session ID
  issue?: GitHubIssue;
  session?: ActiveDelegation;
  julesSessionRaw?: any; // Aus julesSessions array falls keine Delegation
  pr?: PullRequest;
  projectItem?: any;
  status: string;
  issueType: 'MASTER' | 'STANDARD' | 'OTHER';
  sortScore: number;
  isMaster: boolean;
  parentId?: string;
  children: Workstream[];
}

const GITHUB_REPO = 'Vorce-Studios/Vorce';
const ACTIVE_JULES_STATES = new Set(['IN_PROGRESS', 'PAUSED', 'AWAITING_USER_FEEDBACK', 'AWAITING_USER_FEEDBACK_CI_OR_BLOCKER']);

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

const PROJECT_STATUS_COLORS: Record<string, { border: string; bg: string; text: string; borderClass: string }> = {
  Planed: { border: '#6e7681', bg: 'bg-slate-500/20', text: 'text-slate-300', borderClass: 'border-slate-500/40' },
  Started: { border: '#fb8500', bg: 'bg-orange-500/20', text: 'text-orange-300', borderClass: 'border-orange-500/40' },
  Done: { border: '#2da44e', bg: 'bg-green-500/20', text: 'text-green-300', borderClass: 'border-green-500/40' },
  'J-Session_open': { border: '#bf8700', bg: 'bg-yellow-500/20', text: 'text-yellow-300', borderClass: 'border-yellow-500/40' },
  'J-Session_failed': { border: '#bf8700', bg: 'bg-yellow-500/20', text: 'text-yellow-300', borderClass: 'border-yellow-500/40' },
  'J-Session_waiting': { border: '#bf8700', bg: 'bg-yellow-500/20', text: 'text-yellow-300', borderClass: 'border-yellow-500/40' },
  'PR-Checks_Run': { border: '#0969da', bg: 'bg-blue-500/20', text: 'text-blue-300', borderClass: 'border-blue-500/40' },
  'PR-Checks_failed': { border: '#0969da', bg: 'bg-blue-500/20', text: 'text-blue-300', borderClass: 'border-blue-500/40' },
  'PR-Merge_Conflicts': { border: '#cf222e', bg: 'bg-red-500/20', text: 'text-red-300', borderClass: 'border-red-500/40' },
  'Review-PR_needed': { border: '#bf3989', bg: 'bg-pink-500/20', text: 'text-pink-300', borderClass: 'border-pink-500/40' },
  'Review-PR_inRework': { border: '#bf3989', bg: 'bg-pink-500/20', text: 'text-pink-300', borderClass: 'border-pink-500/40' },
  'QA-Test_needed': { border: '#8250df', bg: 'bg-purple-500/20', text: 'text-purple-300', borderClass: 'border-purple-500/40' },
  'QA-Test_running': { border: '#8250df', bg: 'bg-purple-500/20', text: 'text-purple-300', borderClass: 'border-purple-500/40' },
};

function getStatusColor(status: string) {
  return PROJECT_STATUS_COLORS[status] || PROJECT_STATUS_COLORS.Planed;
}

type Phase = 'Phase 1' | 'Phase 2' | 'Phase 3' | 'Phase 4' | 'Phase 5' | 'Phase 6';
const PHASES = ['Phase 1', 'Phase 2', 'Phase 3', 'Phase 4', 'Phase 5', 'Phase 6'];

function getPhase(ws: Workstream): { phase: Phase, label: string, index: number } {
  const s = getDisplayStatus(ws);
  if (s === 'Done') return { phase: 'Phase 6', label: 'Phase 6', index: 5 };
  if (s === 'QA-Test_needed' || s === 'QA-Test_running') return { phase: 'Phase 5', label: 'Phase 5', index: 4 };
  if (s === 'Review-PR_needed' || s === 'Review-PR_inRework') return { phase: 'Phase 4', label: 'Phase 4', index: 3 };
  if (s === 'PR-Checks_Run' || s === 'PR-Checks_failed' || s === 'PR-Merge_Conflicts') return { phase: 'Phase 3', label: 'Phase 3', index: 2 };
  if (s === 'Started' || s === 'J-Session_open' || s === 'J-Session_failed' || s === 'J-Session_waiting') return { phase: 'Phase 2', label: 'Phase 2', index: 1 };
  return { phase: 'Phase 1', label: 'Phase 1', index: 0 };
}

function getDisplayStatus(ws: Workstream): string {
  if (ws.projectItem?.status) return ws.projectItem.status;
  if (ws.issue?.state === 'CLOSED') return 'Done';
  if (ws.pr?.mergeable === 'CONFLICTING') return 'PR-Merge_Conflicts';
  if (ws.pr?.statusCheckRollup?.some(c => c.conclusion === 'FAILURE')) return 'PR-Checks_failed';
  if (ws.pr?.state === 'OPEN') return 'Review-PR_needed';
  const julesState = ws.session?.jules_state || ws.julesSessionRaw?.state;
  if (julesState === 'FAILED') return 'J-Session_failed';
  if (julesState === 'AWAITING_USER_FEEDBACK' || julesState === 'AWAITING_USER_FEEDBACK_CI_OR_BLOCKER' || julesState === 'ESCALATED_TO_USER') return 'J-Session_waiting';
  if (julesState && ACTIVE_JULES_STATES.has(julesState)) return 'J-Session_open';
  if (ws.issue?.labels?.some(l => l.name === 'status: in-progress')) return 'Started';
  return 'Planed';
}

function masterStatus(ws: Workstream): string {
  if (!ws.children.length) return 'Planed';
  const doneChildren = ws.children.filter(c => getDisplayStatus(c) === 'Done').length;
  if (doneChildren === ws.children.length) return 'Done';
  if (doneChildren > 0 || ws.children.some(c => getDisplayStatus(c) !== 'Planed')) return 'Started';
  return 'Planed';
}

function getGHBadgeInfo(ws: Workstream) {
  const ghStatus = getDisplayStatus(ws);
  return { label: ghStatus, ...getStatusColor(ghStatus) };
}

function fixGithubUrl(url: string | undefined): string {
  if (!url) return '';
  return url.replace(/github\.com\/[^/]+\/MapFlow/gi, 'github.com/Vorce-Studios/Vorce');
}

export default function WorkstreamsPage({ issues, sessions, pullRequests, julesSessions, projectItems }: Props) {
  const [filter, setFilter] = useState<'ALL' | 'ACTIVE' | 'ERROR'>('ALL');
  const [isGrouped, setIsGrouped] = useState(true);
  const [sections, setSections] = useState({ planed: true, master: true, standard: true });
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
        wsMap.set(id, { id, status: 'OPEN', issueType: 'STANDARD', sortScore: 0, isMaster: false, children: [] });
      }
      return wsMap.get(id)!;
    };

    // 1. Alle relevanten Issues einfügen
    issues.forEach(issue => {
      if (issue.repo && issue.repo !== GITHUB_REPO) return;
      const ws = getOrAdd(issue.number.toString());
      ws.issue = issue;
      if (issue.title.includes('_MAIs_') || issue.title.includes('Master-Issue') || issue.title.includes('[MASTER]')) {
        ws.isMaster = true;
        ws.issueType = 'MASTER';
      } else {
        ws.isMaster = false;
        ws.issueType = 'STANDARD';
      }
    });

    // 2. Aktive Delegations
    sessions.active_delegations?.forEach(del => {
      const ws = getOrAdd(del.issue_number.toString());
      ws.session = del;
    });

    // 3. Jules Sessions (Raw) Fallback mit repariertem Mapping
    julesSessions?.forEach(js => {
      if (js.repo !== GITHUB_REPO) return;
      if (js.state === 'Done' || js.state === 'Planed' || js.state === 'QUEUED' || js.state === 'COMPLETED') return;

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
      if (pr.repo && pr.repo !== GITHUB_REPO) return;
      if (pr.state !== 'OPEN') return;

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

    // 5. Project Items (GH Status)
    projectItems?.forEach(pi => {
      const repoName = pi.content?.repository || pi.repository?.replace(/^https:\/\/github\.com\//, '');
      if (repoName && repoName !== GITHUB_REPO) return;
      if (pi.content?.number) {
        const ws = getOrAdd(pi.content.number.toString());
        ws.projectItem = pi;
      }
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
        status = 'Done';
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
        // Nur Workstreams als Root zulassen, die auch wirklich ein lokales GitHub Issue haben!
        // Ignoriere nackte Jules Sessions oder lose PRs als Haupt-Workstream (Mist mit Unlinked Tasks).
        if (ws.issue) {
          roots.push(ws);
        }
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
        } else if (childStatuses.includes('Done')) {
          ws.status = 'Done';
          ws.sortScore = Math.max(ws.sortScore, -50);
        } else {
          ws.status = 'Done';
          ws.sortScore = Math.max(ws.sortScore, -100);
        }
      }
    });

    return roots.sort((a, b) => b.sortScore - a.sortScore);
  }, [issues, sessions, pullRequests, julesSessions, projectItems]);

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
    const filtered = result.filter(ws => {
      // 1. Suche-Filter
      if (searchQuery) {
        const q = searchQuery.toLowerCase();
        const matchesQuery = ws.issue?.title?.toLowerCase().includes(q) ||
                             ws.issue?.number?.toString().includes(q) ||
                             ws.pr?.title?.toLowerCase().includes(q) ||
                             ws.pr?.number?.toString().includes(q) ||
                             ws.session?.jules_session_id?.toLowerCase().includes(q);
        if (!matchesQuery) {
          return false;
        }
      } else if (filter !== 'ALL') {
        // In der Standard-Ansicht OHNE aktive Suche wollen wir KEINE abgeschlossenen Workstreams ('Done') sehen!
        if (ws.status === 'Done') {
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
    const ghBadge = getGHBadgeInfo(ws);
    const colors = ws.isMaster ? getStatusColor(masterStatus(ws)) : ghBadge;

    const issueUrl = ws.issue ? fixGithubUrl(ws.issue.url) : '';
    const sessionPrUrl = ws.session?.pr_url ? fixGithubUrl(ws.session.pr_url) : '';
    const prUrl = ws.pr ? fixGithubUrl(ws.pr.url) : '';
    const phaseInfo = getPhase(ws);
    const phasePct = Math.max(3, Math.min(97, (phaseInfo.index / (PHASES.length - 1)) * 100));

    return (
      <div key={ws.id} className="flex flex-col relative mt-2">
        {/* GH Status & Phase Badge (Half Outside) */}
        {!isChild && !ws.isMaster && (
          <div
            className={`absolute -top-3 px-3 py-1 rounded-md text-[11px] font-bold border shadow-lg backdrop-blur-md z-10 flex items-center gap-2 -translate-x-1/2 ${ghBadge.bg} ${ghBadge.text} ${ghBadge.borderClass}`}
            style={{ left: `${phasePct}%` }}
          >
            <span>{ghBadge.label}</span>
          </div>
        )}
        <div
          className={`glass-card overflow-hidden hover:border-slate-700 transition-colors flex flex-col border-l-4 ${isChild ? 'ml-8 my-1 opacity-90 scale-[0.98]' : 'mt-3 mb-3'}`}
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

              {isChild && (
                <span className={`badge ${colors.bg} ${colors.text} border ${colors.borderClass} text-[10px] flex-shrink-0`}>
                  {getDisplayStatus(ws)}
                </span>
              )}

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

          {/* PHASE PROGRESS BAR / SEGMENTED BAR */}
          <div className="px-4 pb-4">
            {ws.isMaster ? (
              <div className="mt-2">
                <div className={`inline-flex items-center px-2 py-1 mb-2 rounded border text-[11px] font-bold ${getStatusColor(masterStatus(ws)).bg} ${getStatusColor(masterStatus(ws)).text} ${getStatusColor(masterStatus(ws)).borderClass}`}>
                  {masterStatus(ws)}
                </div>
                <div className="flex justify-between items-center mb-1.5">
                  <span className="text-[10px] text-slate-400 font-medium">Sub-Issues Fortschritt</span>
                  <span className="text-[10px] text-slate-300 font-bold">
                    {ws.children.filter(c => c.projectItem?.status === 'Done' || c.status === 'Done').length} von {ws.children.length}
                    ({ws.children.length ? Math.round((ws.children.filter(c => c.projectItem?.status === 'Done' || c.status === 'Done').length / ws.children.length) * 100) : 0}%)
                  </span>
                </div>
                <div className="flex gap-1 h-2 w-full">
                  {ws.children.length === 0 ? (
                    <div className="flex-1 rounded-full bg-slate-800/60" />
                  ) : (
                    ws.children.map((c, i) => {
                      const isDone = c.projectItem?.status === 'Done' || c.status === 'Done';
                      const cColor = getStatusColor(getDisplayStatus(c));
                      const bgClass = cColor.bg ? cColor.bg.replace(/\/20|\/35/g, '') : 'bg-slate-600';
                      return <div key={i} className={`flex-1 rounded-full ${isDone ? bgClass : 'bg-slate-800/60'}`} title={c.issue?.title || c.id} />
                    })
                  )}
                </div>
              </div>
            ) : (
              <div className="relative flex items-center justify-between w-full mt-4 pb-6 px-2">
                {/* Background Line */}
                <div className="absolute left-2 right-2 top-1.5 -translate-y-1/2 h-1 bg-slate-800/60 rounded-full" />

                {PHASES.map((p, idx) => {
                  const isActive = idx === phaseInfo.index;
                  const isPast = idx < phaseInfo.index;
                  const bgClass = colors.bg ? colors.bg.replace(/\/20|\/35/g, '') : 'bg-slate-600';
                  const activeBgClass = bgClass.includes('bg-') ? bgClass : 'bg-emerald-500';

                  return (
                    <div key={p} className="relative z-10 flex flex-col items-center">
                      <div className={`w-3 h-3 rounded-full transition-all duration-300 ring-4 ring-slate-900 ${isActive ? activeBgClass + ' shadow-[0_0_10px_rgba(0,0,0,0.5)] scale-125' : isPast ? activeBgClass : 'bg-slate-700'}`} />
                      <span className={`absolute top-5 text-[9px] font-bold tracking-wider uppercase whitespace-nowrap transition-colors ${isActive ? 'text-slate-100' : isPast ? 'text-slate-400' : 'text-slate-600'}`}>
                        {p}
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
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
      <div className="space-y-6">
        {filteredWorkstreams.length === 0 ? (
          <div className="glass-card p-12 text-center text-slate-400 border-dashed border-slate-800">
            Keine Workstreams gefunden für diesen Filter.
          </div>
        ) : (
          <>
            {/* Geplante Issues */}
            {filteredWorkstreams.filter(ws => ws.projectItem?.status === 'Planed').length > 0 && (
              <div className="space-y-2">
                <button onClick={() => setSections(s => ({...s, planed: !s.planed}))} className="flex items-center gap-2 w-full text-left font-bold text-cyan-400 p-2 hover:bg-slate-800/50 rounded-lg transition-colors">
                  {sections.planed ? <ChevronDown className="w-5 h-5" /> : <ChevronRight className="w-5 h-5" />}
                  Geplante Issues ({filteredWorkstreams.filter(ws => ws.projectItem?.status === 'Planed').length})
                </button>
                {sections.planed && (
                  <div className="space-y-1 pl-2">
                    {filteredWorkstreams.filter(ws => ws.projectItem?.status === 'Planed').map(ws => renderWorkstream(ws))}
                  </div>
                )}
              </div>
            )}

            {[
              { id: 'master', label: 'Master-Issues', color: 'text-purple-400', filter: (ws: any) => ws.projectItem?.status !== 'Planed' && ws.issueType === 'MASTER' },
              { id: 'standard', label: 'Standard-Issues', color: 'text-emerald-400', filter: (ws: any) => ws.projectItem?.status !== 'Planed' && ws.issueType !== 'MASTER' }
            ].map(group => {
              const items = filteredWorkstreams.filter(group.filter);
              if (items.length === 0) return null;
              return (
                <div key={group.id} className="space-y-2">
                  <button onClick={() => setSections(s => ({...s, [group.id]: !(s as any)[group.id]}))} className={`flex items-center gap-2 w-full text-left font-bold ${group.color} p-2 hover:bg-slate-800/50 rounded-lg transition-colors`}>
                    {(sections as any)[group.id] ? <ChevronDown className="w-5 h-5" /> : <ChevronRight className="w-5 h-5" />}
                    {group.label} ({items.length})
                  </button>
                  {(sections as any)[group.id] && (
                    <div className="space-y-1 pl-2">
                      {items.map(ws => renderWorkstream(ws))}
                    </div>
                  )}
                </div>
              );
            })}
          </>
        )}
      </div>
    </div>
  );
}
