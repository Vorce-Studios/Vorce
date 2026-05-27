import { useState, useMemo } from 'react';
import { ExternalLink, CheckCircle, XCircle, AlertTriangle, Search } from 'lucide-react';
import type { PullRequest } from '../types';

interface Props {
  pullRequests: PullRequest[];
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

function MergeableBadge({ status }: { status: string }) {
  if (status === 'MERGEABLE') return <span className="badge bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">Mergeable</span>;
  if (status === 'CONFLICTING') return <span className="badge bg-red-500/20 text-red-400 border border-red-500/30">Konflikte</span>;
  return <span className="badge bg-slate-500/20 text-slate-400 border border-slate-500/30">{status}</span>;
}

function ChecksSummary({ checks }: { checks: PullRequest['statusCheckRollup'] }) {
  const passed = checks.filter(c => (c.conclusion === 'SUCCESS' || c.state === 'SUCCESS')).length;
  const failed = checks.filter(c => (c.conclusion === 'FAILURE' || c.state === 'FAILURE' || c.state === 'ERROR')).length;
  const pending = checks.filter(c => (c.status === 'IN_PROGRESS' || c.state === 'PENDING')).length;
  const total = checks.length;

  return (
    <div className="flex items-center gap-2">
      {failed > 0 && (
        <span className="flex items-center gap-1 text-red-400 text-xs">
          <XCircle className="w-3.5 h-3.5" /> {failed}
        </span>
      )}
      {pending > 0 && (
        <span className="flex items-center gap-1 text-amber-400 text-xs">
          <AlertTriangle className="w-3.5 h-3.5" /> {pending}
        </span>
      )}
      <span className="flex items-center gap-1 text-emerald-400 text-xs">
        <CheckCircle className="w-3.5 h-3.5" /> {passed}/{total}
      </span>
    </div>
  );
}

export default function PullRequestsPage({ pullRequests }: Props) {
  const [search, setSearch] = useState('');
  const [mergeFilter, setMergeFilter] = useState<string>('');

  const filtered = useMemo(() => {
    return pullRequests.filter(pr => {
      if (search && !pr.title.toLowerCase().includes(search.toLowerCase()) &&
          !String(pr.number).includes(search)) return false;
      if (mergeFilter && pr.mergeable !== mergeFilter) return false;
      return true;
    });
  }, [pullRequests, search, mergeFilter]);

  const mergeableCount = pullRequests.filter(p => p.mergeable === 'MERGEABLE').length;
  const conflictCount = pullRequests.filter(p => p.mergeable === 'CONFLICTING').length;

  return (
    <div className="space-y-4 animate-in">
      {/* Summary */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="glass-card p-4 text-center">
          <div className="text-2xl font-bold text-white">{pullRequests.length}</div>
          <div className="text-xs text-slate-400 mt-1">Offene PRs</div>
        </div>
        <div className="glass-card p-4 text-center">
          <div className="text-2xl font-bold text-emerald-400">{mergeableCount}</div>
          <div className="text-xs text-slate-400 mt-1">Mergeable</div>
        </div>
        <div className="glass-card p-4 text-center">
          <div className="text-2xl font-bold text-red-400">{conflictCount}</div>
          <div className="text-xs text-slate-400 mt-1">Mit Konflikten</div>
        </div>
      </div>

      {/* Filters */}
      <div className="glass-card p-4">
        <div className="flex flex-wrap gap-3 items-center">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
            <input
              type="text"
              placeholder="PR suchen..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="input-field pl-9"
            />
          </div>
          <div className="flex gap-1 bg-slate-900/40 rounded-lg p-1">
            {[
              { v: '', l: 'Alle' },
              { v: 'MERGEABLE', l: 'Mergeable' },
              { v: 'CONFLICTING', l: 'Konflikte' },
            ].map(f => (
              <button
                key={f.v}
                onClick={() => setMergeFilter(f.v)}
                className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all ${
                  mergeFilter === f.v
                    ? 'bg-purple-600/30 text-purple-300 border border-purple-500/30'
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {f.l}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Table */}
      <div className="glass-card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-700/50 bg-slate-800/30">
                <th className="text-left py-3 px-4 text-slate-400 font-medium w-16">#</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium">Titel</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium">Merge Status</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium">Checks</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium w-28">Aktualisiert</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium w-16">Link</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(pr => (
                <tr key={pr.number} className="border-b border-slate-800/50 hover:bg-slate-800/20 transition-colors">
                  <td className="py-3 px-4 text-cyan-400 font-mono text-xs">{pr.number}</td>
                  <td className="py-3 px-4 text-slate-200 max-w-md">
                    <span className="line-clamp-1">{pr.title}</span>
                  </td>
                  <td className="py-3 px-4"><MergeableBadge status={pr.mergeable} /></td>
                  <td className="py-3 px-4"><ChecksSummary checks={pr.statusCheckRollup || []} /></td>
                  <td className="py-3 px-4 text-slate-500 text-xs">{timeAgo(pr.updatedAt)}</td>
                  <td className="py-3 px-4">
                    <a href={pr.url} target="_blank" rel="noreferrer"
                      className="text-slate-400 hover:text-purple-400 transition-colors">
                      <ExternalLink className="w-4 h-4" />
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
