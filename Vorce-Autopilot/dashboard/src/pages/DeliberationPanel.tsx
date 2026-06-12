import { useState } from 'react';
import { CheckCircle, XCircle, Users, Clock, Zap, ChevronDown, ChevronUp } from 'lucide-react';
import type { DeliberationLogEntry } from '../types';

interface Props {
  deliberations: DeliberationLogEntry[];
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

const PROVIDER_SHORT: Record<string, string> = {
  codex_orchestrator: 'Codex',
  gemini_cli: 'Gemini',
  claude_code: 'Claude',
  kiro_cli: 'Kiro',
  cline_cli: 'Cline',
  copilot_cli: 'Copilot',
  cursor_agent: 'Cursor',
};

const TASK_LABELS: Record<string, string> = {
  planning: 'Planung',
  complex_review: 'Tiefes Review',
  code_review: 'Code Review',
  merge_conflict_resolution: 'Merge-Konflikt',
  qa_disposition: 'QA-Freigabe',
};

export default function DeliberationPanel({ deliberations }: Props) {
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const recent = (deliberations || []).slice().reverse().slice(0, 10);
  const totalCount = (deliberations || []).length;
  const consensusCount = recent.filter(d => d.consensus_reached).length;

  if (recent.length === 0) {
    return (
      <div className="glass-card p-5">
        <div className="flex items-center gap-2 mb-3">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-purple-600 to-pink-500 flex items-center justify-center">
            <Users className="w-4 h-4 text-white" />
          </div>
          <h3 className="text-sm font-semibold text-slate-200">Dual-CEO Deliberation</h3>
        </div>
        <p className="text-xs text-slate-500">Noch keine Deliberationen durchgeführt.</p>
      </div>
    );
  }

  const toggleExpand = (id: string) => {
    setExpandedId(prev => (prev === id ? null : id));
  };

  return (
    <div className="glass-card p-5">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-purple-600 to-pink-500 flex items-center justify-center">
            <Users className="w-4 h-4 text-white" />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-slate-200">CEO & QA Manager Deliberation</h3>
            <p className="text-[10px] text-slate-500">Letzte {recent.length} von {totalCount} gesamt &bull; Klicke zum Ausklappen des Chats</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <div className="text-center">
            <div className="text-lg font-bold text-emerald-400">{consensusCount}</div>
            <div className="text-[9px] text-slate-500">Konsens</div>
          </div>
          <div className="text-center">
            <div className="text-lg font-bold text-amber-400">{recent.length - consensusCount}</div>
            <div className="text-[9px] text-slate-500">Fallback</div>
          </div>
        </div>
      </div>

      {/* Deliberation List */}
      <div className="space-y-3 max-h-[500px] overflow-y-auto pr-1">
        {recent.map((d) => {
          const isExpanded = expandedId === d.deliberation_id;
          return (
            <div
              key={d.deliberation_id}
              className={`p-3 bg-slate-900/40 border rounded-xl hover:border-slate-700/60 transition-all duration-200 ${
                isExpanded ? 'border-purple-500/40 bg-slate-900/60 shadow-lg shadow-purple-500/5' : 'border-slate-800/60'
              }`}
            >
              {/* Summary Clickable Bar */}
              <div
                onClick={() => toggleExpand(d.deliberation_id)}
                className="flex items-center gap-3 cursor-pointer select-none"
              >
                {/* Consensus indicator */}
                <div className="flex-shrink-0">
                  {d.consensus_reached ? (
                    <CheckCircle className="w-4 h-4 text-emerald-400" />
                  ) : (
                    <XCircle className="w-4 h-4 text-amber-400" />
                  )}
                </div>

                {/* Main info */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <span className="text-[10px] font-semibold text-slate-200 capitalize">
                      {TASK_LABELS[d.task_type] || d.task_type.replace(/_/g, ' ')}
                    </span>
                    <span className="text-[8px] text-slate-500 font-mono">{d.deliberation_id}</span>
                  </div>
                  <div className="flex items-center gap-2 text-[10px]">
                    <span className="flex items-center gap-1">
                      <span className="w-1.5 h-1.5 rounded-full bg-cyan-400"></span>
                      <span className="text-slate-400">{PROVIDER_SHORT[d.alpha_provider] || d.alpha_provider}</span>
                    </span>
                    <Zap className="w-2.5 h-2.5 text-slate-600" />
                    <span className="flex items-center gap-1">
                      <span className="w-1.5 h-1.5 rounded-full bg-purple-400"></span>
                      <span className="text-slate-400">{PROVIDER_SHORT[d.beta_provider] || d.beta_provider}</span>
                    </span>
                  </div>
                </div>

                {/* Meta */}
                <div className="flex-shrink-0 text-right flex items-center gap-3">
                  <div className="text-right">
                    <div className="flex items-center gap-1 text-[10px] text-slate-400 justify-end">
                      <Clock className="w-3 h-3 text-slate-500" />
                      <span>{(d.total_duration_ms / 1000).toFixed(1)}s</span>
                    </div>
                    <div className="text-[9px] text-slate-500 mt-0.5">
                      {d.completed_at ? timeAgo(d.completed_at) : '–'}
                    </div>
                  </div>
                  <div className="text-slate-500">
                    {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                  </div>
                </div>
              </div>

              {/* Expanded Chat Log */}
              {isExpanded && (
                <div className="mt-3 pt-3 border-t border-slate-800/80 space-y-3 animate-in fade-in duration-200">
                  {d.rounds && d.rounds.length > 0 ? (
                    d.rounds.map((round, rIdx) => {
                      const isAlpha = round.agent === 'alpha';
                      const providerName = PROVIDER_SHORT[round.provider] || round.provider;
                      const phaseLabel = round.phase === 'proposal' ? 'Vorschlag (Proposal)' :
                                         round.phase === 'critique' ? 'Kritik & Alternativen (Critique)' :
                                         'Synthese & Entscheidung (Synthesis)';

                      return (
                        <div key={rIdx} className="space-y-1">
                          <div className="flex items-center justify-between text-[9px] px-1">
                            <span className={`font-semibold flex items-center gap-1.5 ${isAlpha ? 'text-cyan-400' : 'text-purple-400'}`}>
                              <span className={`w-1.5 h-1.5 rounded-full ${isAlpha ? 'bg-cyan-400' : 'bg-purple-400'}`}></span>
                              {isAlpha ? `CEO (${providerName})` : `QA Manager (${providerName})`}
                            </span>
                            <span className="text-slate-500 font-mono">
                              {phaseLabel} &bull; {round.duration_ms}ms
                            </span>
                          </div>
                          {round.content ? (
                            <div className="bg-slate-950/90 border border-slate-800/80 rounded-lg p-3 max-h-[300px] overflow-y-auto font-mono text-[10px] text-slate-300 whitespace-pre-wrap leading-relaxed select-text">
                              {round.content}
                            </div>
                          ) : (
                            <div className="text-slate-600 italic text-[10px] pl-1">Kein Inhalt aufgezeichnet.</div>
                          )}
                        </div>
                      );
                    })
                  ) : (
                    <div className="text-center text-xs text-slate-500 py-4">
                      Keine Chat-Historie für diesen Task vorhanden (vor Schema-Update durchgeführt).
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
