// useWebSocketEnhanced.ts (Vorce 3.0 Enhanced)
// React Hook für Echtzeit-Datensync via WebSocket mit Fragment-Updates

import { useEffect, useState, useRef, useCallback, useMemo } from 'react';

interface SyncData {
  timestamp: string;
  globalState?: any;
  taskJournal?: any;
  runStates: Array<{
    name: string;
    data: any;
  }>;
}

interface FileUpdate {
  type: 'file-update';
  path: string;
  eventType: 'created' | 'changed' | 'deleted';
  timestamp: string;
  data: {
    fullPath: string;
    size?: number;
    modified?: string;
    exists?: boolean;
  };
}

interface LogUpdate {
  type: 'log-update';
  logs: Array<{
    line: string;
    timestamp: string;
  }>;
  timestamp: string;
}

interface ConnectionUpdate {
  type: 'connection-established';
  timestamp: string;
}

type WebSocketMessage = SyncData | FileUpdate | LogUpdate | ConnectionUpdate;

interface UseWebSocketOptions {
  url?: string;
  onOpen?: (event: Event) => void;
  onClose?: (event: CloseEvent) => void;
  onError?: (event: Event) => void;
  onMessage?: (data: WebSocketMessage) => void;
  onFileUpdate?: (update: FileUpdate) => void;
  onLogUpdate?: (update: LogUpdate) => void;
  onConnectionEstablished?: () => void;
}

interface UseWebSocketEnhancedReturn {
  data: SyncData | null;
  status: 'connecting' | 'connected' | 'disconnected';
  error: string | null;
  lastSync: string | null;
  connectionStatus: 'connected' | 'disconnected' | 'reconnecting';
  connect: () => void;
  disconnect: () => void;
  reconnect: () => void;
  hasUnreadUpdates: boolean;
  unreadUpdatesCount: number;
}

export function useWebSocketEnhanced({
  url = 'ws://localhost:5174',
  onOpen,
  onClose,
  onError,
  onMessage,
  onFileUpdate,
  onLogUpdate,
  onConnectionEstablished
}: UseWebSocketOptions = {}): UseWebSocketEnhancedReturn {
  const [data, setData] = useState<SyncData | null>(null);
  const [status, setStatus] = useState<'connecting' | 'connected' | 'disconnected'>('disconnected');
  const [lastError, setLastError] = useState<string | null>(null);
  const [lastSync, setLastSync] = useState<string | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'connected' | 'disconnected' | 'reconnecting'>('disconnected');
  const [unreadUpdates, setUnreadUpdates] = useState<Set<string>>(new Set());
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectAttemptsRef = useRef(0);
  const syncIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Add file to unread updates
  const markAsUnread = useCallback((filePath: string) => {
    setUnreadUpdates(prev => {
      const newSet = new Set(prev);
      newSet.add(filePath);
      return newSet;
    });
  }, []);

  // Remove file from unread updates
  const markAsRead = useCallback((filePath: string) => {
    setUnreadUpdates(prev => {
      const newSet = new Set(prev);
      newSet.delete(filePath);
      return newSet;
    });
  }, []);

  // Has unread updates
  const hasUnreadUpdates = useMemo(() => unreadUpdates.size > 0, [unreadUpdates.size]);

  // Unread updates count
  const unreadUpdatesCount = unreadUpdates.size;

  // Verbindung herstellen
  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    setStatus('connecting');
    setConnectionStatus('reconnecting');
    setLastError(null);

    try {
      wsRef.current = new WebSocket(url);

      wsRef.current.onopen = (event) => {
        setStatus('connected');
        setConnectionStatus('connected');
        reconnectAttemptsRef.current = 0;
        setLastSync(new Date().toISOString());
        setUnreadUpdates(new Set()); // Clear unread updates on connect
        onOpen?.(event);
        onConnectionEstablished?.();

        // Start periodic sync timestamp updates
        syncIntervalRef.current = setInterval(() => {
          setLastSync(new Date().toISOString());
        }, 30000); // Every 30 seconds
      };

      wsRef.current.onclose = (event) => {
        setStatus('disconnected');
        setConnectionStatus('disconnected');
        onClose?.(event);

        // Clear sync interval
        if (syncIntervalRef.current) {
          clearInterval(syncIntervalRef.current);
          syncIntervalRef.current = null;
        }

        // Auto-reconnect nach 5 Sekunden
        if (!event.wasClean) {
          reconnectAttemptsRef.current++;
          if (reconnectAttemptsRef.current < 5) {
            reconnectTimeoutRef.current = setTimeout(() => {
              connect();
            }, 5000);
          }
        }
      };

      wsRef.current.onerror = (event) => {
        setLastError('WebSocket connection error');
        onError?.(event);
      };

      wsRef.current.onmessage = (event) => {
        try {
          const message: WebSocketMessage = JSON.parse(event.data);

          // Handle different message types
          switch (message.type) {
            case 'file-update':
              const fileUpdate = message as FileUpdate;
              setData(prev => {
                if (!prev) return prev;

                // Update only the affected fragment
                const updatedRunStates = prev.runStates.map(runState => {
                  if (fileUpdate.path.startsWith(runState.name)) {
                    return {
                      ...runState,
                      data: {
                        ...runState.data,
                        lastUpdated: fileUpdate.timestamp,
                        [fileUpdate.data.fullPath]: fileUpdate.data
                      }
                    };
                  }
                  return runState;
                });

                return {
                  ...prev,
                  timestamp: fileUpdate.timestamp,
                  runStates: updatedRunStates
                };
              });

              setLastSync(fileUpdate.timestamp);
              onFileUpdate?.(fileUpdate);
              markAsUnread(fileUpdate.path);
              break;

            case 'log-update':
              const logUpdate = message as LogUpdate;
              setLastSync(logUpdate.timestamp);
              onLogUpdate?.(logUpdate);
              break;

            case 'connection-established':
              const connUpdate = message as ConnectionUpdate;
              setLastSync(connUpdate.timestamp);
              onConnectionEstablished?.();
              break;

            default:
              // Handle original sync data format
              const syncData = message as SyncData;
              setData(syncData);
              setLastSync(syncData.timestamp);
              onMessage?.(syncData);
          }
        } catch (error) {
          console.error('Failed to parse WebSocket message:', error);
        }
      };

    } catch (error) {
      setLastError('Failed to create WebSocket connection');
      console.error('WebSocket connection error:', error);
    }
  }, [url, onOpen, onClose, onError, onMessage, onFileUpdate, onLogUpdate, onConnectionEstablished, markAsUnread]);

  // Verbindung trennen
  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }

    if (syncIntervalRef.current) {
      clearInterval(syncIntervalRef.current);
      syncIntervalRef.current = null;
    }

    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }

    setStatus('disconnected');
    setConnectionStatus('disconnected');
  }, []);

  // Verbindung bei URL-Änderung neu aufbauen
  useEffect(() => {
    connect();
    return () => disconnect();
  }, [connect, disconnect]);

  // Aufräumen bei Komponenten-Unmount
  useEffect(() => {
    return () => {
      disconnect();
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (syncIntervalRef.current) {
        clearInterval(syncIntervalRef.current);
      }
    };
  }, [disconnect]);

  return {
    data,
    status,
    error: lastError,
    lastSync,
    connectionStatus,
    connect,
    disconnect,
    reconnect: connect,
    hasUnreadUpdates,
    unreadUpdatesCount
  };
}

// Hook for consuming log updates
export function useLiveLog() {
  const [logs, setLogs] = useState<Array<{ line: string; timestamp: string }>>([]);
  const maxLogs = 50;

  const handleLogUpdate = useCallback((update: LogUpdate) => {
    setLogs(prev => {
      const newLogs = [...update.logs, ...prev];
      return newLogs.slice(0, maxLogs);
    });
  }, [maxLogs]);

  const { connectionStatus } = useWebSocketEnhanced({
    onLogUpdate: handleLogUpdate
  });

  return {
    logs,
    connectionStatus,
    clearLogs: () => setLogs([])
  };
}

// Hook for consuming file updates
export function useFileUpdates() {
  const [updates, setUpdates] = useState<Array<FileUpdate>>([]);
  const maxHistory = 20;

  const handleFileUpdate = useCallback((update: FileUpdate) => {
    setUpdates(prev => {
      const newUpdates = [update, ...prev];
      return newUpdates.slice(0, maxHistory);
    });
  }, [maxHistory]);

  const { connectionStatus } = useWebSocketEnhanced({
    onFileUpdate: handleFileUpdate
  });

  return {
    updates,
    connectionStatus,
    clearUpdates: () => setUpdates([])
  };
}

// Legacy compatibility
export function useWebSocket(options?: UseWebSocketOptions) {
  return useWebSocketEnhanced(options);
}

export function useAutoRefresh(jsonPath?: string, _intervalMs?: number) {
  const { data, status } = useWebSocketEnhanced({
    url: 'ws://localhost:5174'
  });

  return {
    data,
    status,
    loading: status === 'connecting',
    error: status === 'disconnected' ? null : undefined
  };
}