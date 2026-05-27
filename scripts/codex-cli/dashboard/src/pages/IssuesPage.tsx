import { useState, useMemo } from 'react';
import { Search, ExternalLink, Filter } from 'lucide-react';
import type { GitHubIssue } from '../types';

interface Props {
  issues: GitHubIssue[];
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

export default function IssuesPage({ issues }: Props) {
  const [search, setSearch] = useState('');
  const [labelFilter, setLabelFilter] = useState('');
  const [stateFilter, setStateFilter] = useState<'ALL' | 'OPEN' | 'CLOSED'>('OPEN');
  const [page, setPage] = useState(0);
  const PAGE_SIZE = 25;

  // Collect unique labels
  const allLabels = useMemo(() => {
    const set = new Set<string>();
    issues.forEach(i => i.labels.forEach(l => set.add(l.name)));
    return Array.from(set).sort();
  }, [issues]);

  const filtered = useMemo(() => {
    return issues.filter(issue => {
      if (stateFilter !== 'ALL' && issue.state !== stateFilter) return false;
      if (search && !issue.title.toLowerCase().includes(search.toLowerCase()) &&
          !String(issue.number).includes(search)) return false;
      if (labelFilter && !issue.labels.some(l => l.name === labelFilter)) return false;
      return true;
    });
  }, [issues, search, labelFilter, stateFilter]);

  const paged = filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);
  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);

  return (
    <div className="space-y-4 animate-in">
      {/* Filters */}
      <div className="glass-card p-4">
        <div className="flex flex-wrap gap-3 items-center">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
            <input
              type="text"
              placeholder="Issue suchen..."
              value={search}
              onChange={e => { setSearch(e.target.value); setPage(0); }}
              className="input-field pl-9"
            />
          </div>
          <div className="relative min-w-[180px]">
            <Filter className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
            <select
              value={labelFilter}
              onChange={e => { setLabelFilter(e.target.value); setPage(0); }}
              className="input-field pl-9 appearance-none cursor-pointer"
            >
              <option value="">Alle Labels</option>
              {allLabels.map(l => <option key={l} value={l}>{l}</option>)}
            </select>
          </div>
          <div className="flex gap-1 bg-slate-900/40 rounded-lg p-1">
            {(['ALL', 'OPEN', 'CLOSED'] as const).map(s => (
              <button
                key={s}
                onClick={() => { setStateFilter(s); setPage(0); }}
                className={`px-3 py-1.5 text-xs font-medium rounded-md transition-all ${
                  stateFilter === s
                    ? 'bg-purple-600/30 text-purple-300 border border-purple-500/30'
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {s === 'ALL' ? 'Alle' : s === 'OPEN' ? 'Offen' : 'Geschlossen'}
              </button>
            ))}
          </div>
          <span className="text-xs text-slate-500">{filtered.length} Ergebnisse</span>
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
                <th className="text-left py-3 px-4 text-slate-400 font-medium">Labels</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium w-24">Status</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium w-28">Aktualisiert</th>
                <th className="text-left py-3 px-4 text-slate-400 font-medium w-16">Link</th>
              </tr>
            </thead>
            <tbody>
              {paged.map(issue => (
                <tr key={issue.number} className="border-b border-slate-800/50 hover:bg-slate-800/20 transition-colors">
                  <td className="py-3 px-4 text-purple-400 font-mono text-xs">{issue.number}</td>
                  <td className="py-3 px-4 text-slate-200 max-w-md">
                    <span className="line-clamp-1">{issue.title}</span>
                  </td>
                  <td className="py-3 px-4">
                    <div className="flex flex-wrap gap-1 max-w-xs">
                      {issue.labels.slice(0, 3).map(l => (
                        <span key={l.id}
                          className="badge border text-xs cursor-pointer hover:opacity-80"
                          style={{
                            borderColor: `#${l.color}40`,
                            backgroundColor: `#${l.color}15`,
                            color: `#${l.color}`,
                          }}
                          onClick={() => { setLabelFilter(l.name); setPage(0); }}
                        >
                          {l.name}
                        </span>
                      ))}
                      {issue.labels.length > 3 && (
                        <span className="badge bg-slate-700/40 text-slate-400">+{issue.labels.length - 3}</span>
                      )}
                    </div>
                  </td>
                  <td className="py-3 px-4">
                    <span className={`badge ${
                      issue.state === 'OPEN' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-slate-500/20 text-slate-400'
                    }`}>
                      {issue.state === 'OPEN' ? 'Offen' : 'Geschlossen'}
                    </span>
                  </td>
                  <td className="py-3 px-4 text-slate-500 text-xs">{timeAgo(issue.updatedAt)}</td>
                  <td className="py-3 px-4">
                    <a href={issue.url} target="_blank" rel="noreferrer"
                      className="text-slate-400 hover:text-purple-400 transition-colors">
                      <ExternalLink className="w-4 h-4" />
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-slate-700/50">
            <button
              onClick={() => setPage(p => Math.max(0, p - 1))}
              disabled={page === 0}
              className="btn-secondary text-xs disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Zurück
            </button>
            <span className="text-xs text-slate-400">
              Seite {page + 1} von {totalPages}
            </span>
            <button
              onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))}
              disabled={page >= totalPages - 1}
              className="btn-secondary text-xs disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Weiter
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
