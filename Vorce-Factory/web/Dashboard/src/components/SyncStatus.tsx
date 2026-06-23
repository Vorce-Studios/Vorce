import { RefreshCw, Wifi, WifiOff, AlertCircle } from 'lucide-react';
import { useWebSocketEnhanced } from '../hooks/useWebSocketEnhanced';

interface SyncStatusProps {
  onManualRefresh?: () => void;
}

export function SyncStatus({ onManualRefresh }: SyncStatusProps) {
  const {
    lastSync,
    connectionStatus,
    hasUnreadUpdates,
    unreadUpdatesCount,
    reconnect
  } = useWebSocketEnhanced();

  const formatTimestamp = (timestamp: string | null) => {
    if (!timestamp) return 'N/A';
    return new Date(timestamp).toLocaleTimeString('de-DE', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  };

  const getConnectionIcon = () => {
    switch (connectionStatus) {
      case 'connected':
        return <Wifi className="w-4 h-4 text-green-400" />;
      case 'reconnecting':
        return <RefreshCw className="w-4 h-4 text-yellow-400 animate-spin" />;
      case 'disconnected':
        return <WifiOff className="w-4 h-4 text-red-400" />;
      default:
        return <WifiOff className="w-4 h-4 text-slate-400" />;
    }
  };

  const getConnectionColor = () => {
    switch (connectionStatus) {
      case 'connected':
        return 'text-green-400';
      case 'reconnecting':
        return 'text-yellow-400';
      case 'disconnected':
        return 'text-red-400';
      default:
        return 'text-slate-400';
    }
  };

  const getStatusText = () => {
    switch (connectionStatus) {
      case 'connected':
        return 'Verbunden';
      case 'reconnecting':
        return 'Verbinde neu...';
      case 'disconnected':
        return 'Getrennt';
      default:
        return 'Unbekannt';
    }
  };

  const getSyncStatus = () => {
    if (!lastSync) {
      return {
        text: 'Kein Sync',
        color: 'text-slate-400'
      };
    }

    const now = new Date();
    const syncTime = new Date(lastSync);
    const diffMs = now.getTime() - syncTime.getTime();
    const diffSeconds = Math.floor(diffMs / 1000);

    if (diffSeconds < 10) {
      return {
        text: 'Echtzeit',
        color: 'text-green-400'
      };
    } else if (diffSeconds < 30) {
      return {
        text: 'Aktuell',
        color: 'text-blue-400'
      };
    } else if (diffSeconds < 60) {
      return {
        text: 'Vor ' + diffSeconds + 's',
        color: 'text-yellow-400'
      };
    } else {
      return {
        text: formatTimestamp(lastSync),
        color: 'text-slate-400'
      };
    }
  };

  const syncStatus = getSyncStatus();

  return (
    <div className="flex items-center gap-3 px-3 py-2 rounded-lg bg-slate-800/50 border border-slate-700">
      {/* Verbindung Status */}
      <div className="flex items-center gap-2">
        {getConnectionIcon()}
        <span className={`text-sm font-medium ${getConnectionColor()}`}>
          {getStatusText()}
        </span>
      </div>

      {/* Trennlinie */}
      <div className="h-4 w-px bg-slate-600"></div>

      {/* Sync Status */}
      <div className="flex items-center gap-2">
        <span className="text-xs text-slate-400">Letzter Sync:</span>
        <span className={`text-sm font-medium ${syncStatus.color}`}>
          {syncStatus.text}
        </span>
      </div>

      {/* Unread Updates Badge */}
      {hasUnreadUpdates && (
        <>
          <div className="h-4 w-px bg-slate-600"></div>
          <div className="flex items-center gap-1">
            <AlertCircle className="w-3 h-3 text-amber-400" />
            <span className="text-xs font-medium text-amber-400">
              {unreadUpdatesCount} ungelesen
            </span>
          </div>
        </>
      )}

      {/* Manual Refresh Button */}
      {onManualRefresh && (
        <>
          <div className="h-4 w-px bg-slate-600"></div>
          <button
            onClick={onManualRefresh}
            className="p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-700 rounded-md transition-colors"
            title="Manuell aktualisieren"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </>
      )}

      {/* Reconnect Button */}
      {connectionStatus === 'disconnected' && (
        <button
          onClick={reconnect}
          className="ml-auto px-3 py-1 text-xs bg-purple-600/20 text-purple-400 hover:bg-purple-600/30 rounded-md transition-colors"
        >
          Neu verbinden
        </button>
      )}
    </div>
  );
}
