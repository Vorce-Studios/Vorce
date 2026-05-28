import { ExternalLink } from 'lucide-react';
import type { ActiveSessions } from '../types';

interface Props {
  sessions: ActiveSessions;
  julesSessions?: any[];
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

function StateBadge({ state }: { state: string }) {
  const configs: Record<string, { bg: string; text: string; label: string }> = {
    'IN_PROGRESS': { bg: 'bg-blue-500/20 border-blue-500/30', text: 'text-blue-400', label: 'In Progress' },
    'AWAITING_USER_FEEDBACK': { bg: 'bg-amber-500/20 border-amber-500/30', text: 'text-amber-400', label: 'Awaiting Feedback' },
    'AWAITING_PLAN_APPROVAL': { bg: 'bg-yellow-500/20 border-yellow-500/30', text: 'text-yellow-400', label: 'Awaiting Plan' },
    'COMPLETED': { bg: 'bg-emerald-500/20 border-emerald-500/30', text: 'text-emerald-400', label: 'Completed' },
    'FAILED': { bg: 'bg-red-500/20 border-red-500/30', text: 'text-red-400', label: 'Failed' },
  };
  const cfg = configs[state] || { bg: 'bg-slate-500/20 border-slate-500/30', text: 'text-slate-400', label: state };
  return <span className={`badge ${cfg.bg} ${cfg.text} border`}>{cfg.label}</span>;
}

function ReviewBadge({ status }: { status: string }) {
  const configs: Record<string, { bg: string; text: string }> = {
    'completed': { bg: 'bg-emerald-500/20', text: 'text-emerald-400' },
    'running': { bg: 'bg-blue-500/20', text: 'text-blue-400' },
    'pending': { bg: 'bg-amber-500/20', text: 'text-amber-400' },
  };
  const cfg = configs[status] || { bg: 'bg-slate-500/20', text: 'text-slate-400' };
  return <span className={`badge ${cfg.bg} ${cfg.text}`}>{status}</span>;
}

export default function SessionsPage({ sessions, julesSessions }: Props) {
  const delegations = sessions.active_delegations || [];
  const reviewQueue = sessions.review_queue || [];
  const completedItems = sessions.completed_this_session || [];
  const julesList = julesSessions || [];

  return (
    <div className="space-y-6 animate-in">
      {/* Active Delegations */}
      <div className="glass-card p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-slate-200">
            Aktive Delegierungen
            <span className="ml-2 badge bg-purple-500/20 text-purple-400">{delegations.length}</span>
          </h3>
        </div>
        {delegations.length === 0 ? (
          <p className="text-slate-500 text-sm">Keine aktiven Delegierungen</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-700/50">
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Issue</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Titel</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Status</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Retries</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Letzter Check</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Delegiert</th>
                </tr>
              </thead>
              <tbody>
                {delegations.map((d) => (
                  <tr key={d.jules_session_id} className="border-b border-slate-800/50 hover:bg-slate-800/30 transition-colors">
                    <td className="py-3 px-3 text-purple-400 font-mono">#{d.issue_number}</td>
                    <td className="py-3 px-3 text-slate-200 max-w-xs truncate">{d.issue_title}</td>
                    <td className="py-3 px-3"><StateBadge state={d.jules_state} /></td>
                    <td className="py-3 px-3 text-slate-400">{d.retry_count}</td>
                    <td className="py-3 px-3 text-slate-400">{timeAgo(d.last_checked_at)}</td>
                    <td className="py-3 px-3 text-slate-400">{timeAgo(d.delegated_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Review Queue */}
      <div className="glass-card p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-slate-200">
            Review Queue
            <span className="ml-2 badge bg-cyan-500/20 text-cyan-400">{reviewQueue.length}</span>
          </h3>
        </div>
        {reviewQueue.length === 0 ? (
          <p className="text-slate-500 text-sm">Keine Reviews in der Queue</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-700/50">
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Issue</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">PR</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Review Status</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Link</th>
                </tr>
              </thead>
              <tbody>
                {reviewQueue.map((r) => (
                  <tr key={`${r.issue_number}-${r.pr_number}`} className="border-b border-slate-800/50 hover:bg-slate-800/30 transition-colors">
                    <td className="py-3 px-3 text-purple-400 font-mono">#{r.issue_number}</td>
                    <td className="py-3 px-3 text-cyan-400 font-mono">#{r.pr_number}</td>
                    <td className="py-3 px-3"><ReviewBadge status={r.review_status} /></td>
                    <td className="py-3 px-3">
                      <a href={r.pr_url} target="_blank" rel="noreferrer"
                        className="text-slate-400 hover:text-purple-400 transition-colors inline-flex items-center gap-1">
                        <ExternalLink className="w-3.5 h-3.5" /> Öffnen
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Completed This Session */}
      <div className="glass-card p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-slate-200">
            Abgeschlossen (diese Session)
            <span className="ml-2 badge bg-emerald-500/20 text-emerald-400">{completedItems.length}</span>
          </h3>
        </div>
        {completedItems.length === 0 ? (
          <p className="text-slate-500 text-sm">Noch keine abgeschlossenen Aufgaben</p>
        ) : (
          <div className="overflow-x-auto max-h-96 overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-slate-800/90 backdrop-blur-sm">
                <tr className="border-b border-slate-700/50">
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Issue</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Ergebnis</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Abgeschlossen</th>
                </tr>
              </thead>
              <tbody>
                {completedItems.slice().reverse().slice(0, 50).map((c, i) => (
                  <tr key={`${c.issue_number}-${i}`} className="border-b border-slate-800/50 hover:bg-slate-800/30 transition-colors">
                    <td className="py-2.5 px-3 text-purple-400 font-mono">#{c.issue_number}</td>
                    <td className="py-2.5 px-3">
                      <span className={`badge ${c.result === 'completed' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'}`}>
                        {c.result}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-slate-400">{timeAgo(c.completed_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Jules API Sessions */}
      <div className="glass-card p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-slate-200">
            Jules API Sessions (Vorce & MapFlow)
            <span className="ml-2 badge bg-purple-500/20 text-purple-400">{julesList.length}</span>
          </h3>
        </div>
        {julesList.length === 0 ? (
          <p className="text-slate-500 text-sm">Keine Jules API Sessions gefunden. Bitte stelle sicher, dass der Autopilot-Hintergrunddienst läuft.</p>
        ) : (
          <div className="overflow-x-auto max-h-[500px] overflow-y-auto pr-1">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-slate-900/90 backdrop-blur-sm">
                <tr className="border-b border-slate-700/50">
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Session ID</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Repository / Issue</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Titel</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Status</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Aktualisiert</th>
                  <th className="text-left py-3 px-3 text-slate-400 font-medium">Link</th>
                </tr>
              </thead>
              <tbody>
                {julesList.map((s) => {
                  const sessionId = s.name.split('/').pop() || s.name;
                  const isVorce = s.repo.includes('Vorce');
                  const repoColor = isVorce ? 'text-cyan-400' : 'text-amber-400';
                  
                  return (
                    <tr key={s.name} className="border-b border-slate-800/50 hover:bg-slate-800/30 transition-colors">
                      <td className="py-3 px-3 text-slate-400 font-mono text-xs">{sessionId}</td>
                      <td className="py-3 px-3">
                        <span className={`font-medium ${repoColor}`}>{s.repo.split('/').pop()}</span>
                        {s.issueNumber && (
                          <span className="ml-1.5 text-purple-400 font-mono">#{s.issueNumber}</span>
                        )}
                      </td>
                      <td className="py-3 px-3 text-slate-200 max-w-xs truncate">{s.title}</td>
                      <td className="py-3 px-3"><StateBadge state={s.state} /></td>
                      <td className="py-3 px-3 text-slate-400 text-xs">{timeAgo(s.updatedAt)}</td>
                      <td className="py-3 px-3">
                        <a href={s.url} target="_blank" rel="noreferrer"
                          className="text-slate-400 hover:text-purple-400 transition-colors inline-flex items-center gap-1">
                          <ExternalLink className="w-3.5 h-3.5" />
                        </a>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
