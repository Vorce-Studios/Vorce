import { Activity, Bug, Eye, EyeOff, MessageSquare, RefreshCw, X } from 'lucide-react';
import { useMemo, useState } from 'react';
import { useA2ALive } from '../hooks/useA2ALive';
import type { A2AMessage } from '../hooks/useA2ALive';

// ── Styling helpers ──

function typeColor(type: string): string {
  switch (type) {
    case 'TaskProgress':
      return 'text-blue-300 border-blue-500/30 bg-blue-500/10';
    case 'CritiqueFeedback':
      return 'text-orange-300 border-orange-500/30 bg-orange-500/10';
    case 'a2a.message':
      return 'text-slate-300 border-slate-500/30 bg-slate-500/10';
    default:
      return 'text-purple-300 border-purple-500/30 bg-purple-500/10';
  }
}

function typeBadgeColor(type: string): string {
  switch (type) {
    case 'TaskProgress':
      return 'bg-blue-600/30 text-blue-200';
    case 'CritiqueFeedback':
      return 'bg-orange-600/30 text-orange-200';
    case 'a2a.message':
      return 'bg-slate-600/30 text-slate-200';
    default:
      return 'bg-purple-600/30 text-purple-200';
  }
}

function sourceIcon(source: string) {
  const s = source.toLowerCase();
  if (s.includes('ceo')) return <Activity className="w-3 h-3 text-amber-400" />;
  if (s.includes('qa') || s.includes('manager')) return <Bug className="w-3 h-3 text-emerald-400" />;
  if (s.includes('orchestrator')) return <RefreshCw className="w-3 h-3 text-cyan-400" />;
  return <MessageSquare className="w-3 h-3 text-slate-400" />;
}

function formatTimestamp(ts: string): string {
  try {
    const d = new Date(ts);
    if (Number.isNaN(d.getTime())) return 'N/A';
    return d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  } catch {
    return 'N/A';
  }
}

function truncatedJson(obj: unknown, maxLen = 120): string {
  try {
    const str = JSON.stringify(obj, null, 1);
    if (str.length <= maxLen) return str;
    return str.slice(0, maxLen) + '\u2026';
  } catch {
    return String(obj);
  }
}

// ── Sub-components ──

function A2AMessageCard({ message }: { message: A2AMessage }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div
      className={`rounded-lg border px-3 py-2 cursor-pointer transition-colors hover:brightness-110 ${typeColor(message.type)}`}
      onClick={() => setExpanded(prev => !prev)}
    >
      <div className="flex items-center gap-2 text-xs">
        {sourceIcon(message.source)}
        <span className={`px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase ${typeBadgeColor(message.type)}`}>
          {message.type}
        </span>
        <span className="text-slate-400 font-medium truncate flex-1">
          {message.source}
        </span>
        <span className="text-slate-500 shrink-0">
          {formatTimestamp(message.timestamp)}
        </span>
      </div>

      {expanded && (
        <pre className="mt-2 text-[11px] text-slate-300 font-mono leading-relaxed overflow-x-auto whitespace-pre-wrap">
          {truncatedJson(message.payload, 2000)}
        </pre>
      )}
    </div>
  );
}

// ── Main component ──

interface A2ALiveMonitorProps {
  maxMessages?: number;
  filterTarget?: string;
}

export default function A2ALiveMonitor({
  maxMessages = 100,
  filterTarget
}: A2ALiveMonitorProps) {
  const {
    messages,
    unreadCount,
    markAllRead,
    clearMessages,
    connectionStatus
  } = useA2ALive({ maxMessages, filterTarget });

  const [paused, setPaused] = useState(false);
  const [typeFilter, setTypeFilter] = useState<string | null>(null);

  const availableTypes = useMemo(() => {
    const types = new Set<string>();
    for (const m of messages) {
      types.add(m.type);
    }
    return Array.from(types);
  }, [messages]);

  const displayedMessages = useMemo(() => {
    let msgs = paused ? messages : messages;
    if (typeFilter) {
      msgs = msgs.filter(m => m.type === typeFilter);
    }
    return msgs;
  }, [messages, paused, typeFilter]);

  const statusColor = connectionStatus === 'connected'
    ? 'text-green-400'
    : connectionStatus === 'reconnecting'
      ? 'text-yellow-400'
      : 'text-red-400';

  const statusText = connectionStatus === 'connected'
    ? 'Verbunden'
    : connectionStatus === 'reconnecting'
      ? 'Wiederverbinden...'
      : 'Getrennt';

  return (
    <div className="rounded-xl bg-slate-900 border border-slate-700 overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-slate-700 bg-slate-800/50">
        <h3 className="text-sm font-semibold text-slate-200 flex items-center gap-2">
          <Activity className="w-4 h-4 text-cyan-400" />
          A2A Live Monitor
        </h3>

        <span className={'text-[10px] font-medium ' + statusColor}>
          {'\u25CF'} {statusText}
        </span>

        {unreadCount > 0 && (
          <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-cyan-600/30 text-cyan-300 font-semibold">
            {unreadCount} neu
          </span>
        )}

        <div className="ml-auto flex items-center gap-2">
          {availableTypes.length > 1 && (
            <select
              value={typeFilter || ''}
              onChange={e => setTypeFilter(e.target.value || null)}
              className="text-[11px] bg-slate-700 text-slate-300 border border-slate-600 rounded px-1.5 py-0.5 outline-none focus:border-cyan-500"
            >
              <option value="">Alle Typen</option>
              {availableTypes.map(t => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
          )}

          <button
            onClick={() => setPaused(prev => !prev)}
            className="p-1 text-slate-400 hover:text-slate-200 hover:bg-slate-700 rounded transition-colors"
            title={paused ? 'Feed fortsetzen' : 'Feed pausieren'}
          >
            {paused ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
          </button>

          {unreadCount > 0 && (
            <button
              onClick={markAllRead}
              className="text-[10px] px-1.5 py-0.5 text-slate-400 hover:text-slate-200 hover:bg-slate-700 rounded transition-colors"
            >
              Als gelesen
            </button>
          )}

          <button
            onClick={clearMessages}
            className="p-1 text-slate-400 hover:text-red-400 hover:bg-slate-700 rounded transition-colors"
            title="Alle Nachrichten loeschen"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* Message List */}
      <div className="overflow-y-auto" style={{ maxHeight: '480px' }}>
        {displayedMessages.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 text-slate-500 gap-2">
            <MessageSquare className="w-8 h-8 opacity-40" />
            <span className="text-sm">Keine A2A-Nachrichten</span>
            {connectionStatus !== 'connected' && (
              <span className="text-[10px] text-yellow-500">Warte auf Verbindung...</span>
            )}
          </div>
        ) : (
          <div className="flex flex-col gap-1.5 p-3">
            {displayedMessages.map((msg, idx) => (
              <A2AMessageCard key={msg.id + '-' + idx} message={msg} />
            ))}
          </div>
        )}
      </div>

      {/* Footer Stats */}
      <div className="flex items-center justify-between px-4 py-2 border-t border-slate-700 bg-slate-800/30 text-[10px] text-slate-500">
        <span>{messages.length} Nachrichten insgesamt</span>
        {paused && <span className="text-yellow-500">Pausiert</span>}
        {typeFilter && <span>Gefiltert: {typeFilter}</span>}
      </div>
    </div>
  );
}
