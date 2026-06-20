import { X, ScrollText, AlertTriangle, Info, CheckCircle } from 'lucide-react';
import { useLiveLog } from '../hooks/useWebSocketEnhanced';

interface LiveLogMonitorProps {
  visible?: boolean;
  onClose?: () => void;
  maxHeight?: string;
}

export function LiveLogMonitor({ visible = true, onClose, maxHeight = "300px" }: LiveLogMonitorProps) {
  const { logs, connectionStatus, clearLogs } = useLiveLog();

  const getLogIcon = (line: string) => {
    if (line.toLowerCase().includes('error') || line.toLowerCase().includes('failed')) {
      return <AlertTriangle className="w-3 h-3 text-red-400" />;
    } else if (line.toLowerCase().includes('warning') || line.toLowerCase().includes('warn')) {
      return <AlertTriangle className="w-3 h-3 text-yellow-400" />;
    } else if (line.toLowerCase().includes('success') || line.toLowerCase().includes('completed')) {
      return <CheckCircle className="w-3 h-3 text-green-400" />;
    } else {
      return <Info className="w-3 h-3 text-blue-400" />;
    }
  };

  const getLogColor = (line: string) => {
    if (line.toLowerCase().includes('error') || line.toLowerCase().includes('failed')) {
      return 'text-red-400';
    } else if (line.toLowerCase().includes('warning') || line.toLowerCase().includes('warn')) {
      return 'text-yellow-400';
    } else if (line.toLowerCase().includes('success') || line.toLowerCase().includes('completed')) {
      return 'text-green-400';
    } else {
      return 'text-slate-300';
    }
  };

  const formatLogTime = (timestamp: string) => {
    return new Date(timestamp).toLocaleTimeString('de-DE', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  };

  if (!visible || logs.length === 0) {
    return null;
  }

  return (
    <div className="w-full bg-slate-800/90 border border-slate-700 rounded-lg overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-slate-800 border-b border-slate-700">
        <div className="flex items-center gap-2">
          <ScrollText className="w-4 h-4 text-cyan-400" />
          <h3 className="text-sm font-semibold text-slate-200">Live-Log Monitor</h3>
          <span className="text-xs text-slate-400">
            ({logs.length} Einträge)
          </span>
          <div className={`w-2 h-2 rounded-full ml-2 ${
            connectionStatus === 'connected' ? 'bg-green-400 animate-pulse' : 'bg-yellow-400'
          }`}></div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={clearLogs}
            className="p-1 text-slate-400 hover:text-slate-200 hover:bg-slate-700 rounded transition-colors"
            title="Logs leeren"
          >
            <X className="w-4 h-4" />
          </button>
          {onClose && (
            <button
              onClick={onClose}
              className="p-1 text-slate-400 hover:text-slate-200 hover:bg-slate-700 rounded transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Log Content */}
      <div
        className="px-4 py-2 overflow-y-auto text-xs font-mono"
        style={{ maxHeight }}
      >
        {logs.map((log, index) => (
          <div
            key={`${log.timestamp}-${index}`}
            className="flex gap-2 py-0.5 hover:bg-slate-700/50 rounded px-1 transition-colors"
          >
            {/* Timestamp */}
            <span className="text-slate-500 min-w-[60px]">
              {formatLogTime(log.timestamp)}
            </span>

            {/* Icon */}
            <div className="flex-shrink-0 mt-0.5">
              {getLogIcon(log.line)}
            </div>

            {/* Log Line */}
            <span className={getLogColor(log.line)}>
              {log.line}
            </span>
          </div>
        ))}

        {/* Empty state */}
        {logs.length === 0 && (
          <div className="text-center py-8 text-slate-500">
            Keine Log-Einträge verfügbar
          </div>
        )}
      </div>
    </div>
  );
}
