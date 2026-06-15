// useWebSocket.ts (Vorce 3.0)
// React Hook für Echtzeit-Datensync via WebSocket

import { useEffect, useState, useRef, useCallback } from 'react';

interface SyncData {
  timestamp: string;
  globalState?: any;
  taskJournal?: any;
  runStates: Array<{
    name: string;
    data: any;
  }>;
}

interface UseWebSocketOptions {
  url?: string;
  onOpen?: (event: Event) => void;
  onClose?: (event: CloseEvent) => void;
  onError?: (event: Event) => void;
  onMessage?: (data: SyncData) => void;
}

export function useWebSocket({
  url = 'ws://localhost:5174',
  onOpen,
  onClose,
  onError,
  onMessage
}: UseWebSocketOptions = {}) {
  const [data, setData] = useState<SyncData | null>(null);
  const [status, setStatus] = useState<'connecting' | 'connected' | 'disconnected'>('disconnected');
  const [lastError, setLastError] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectAttemptsRef = useRef(0);

  // Verbindung herstellen
  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    setStatus('connecting');
    setLastError(null);

    try {
      wsRef.current = new WebSocket(url);

      wsRef.current.onopen = (event) => {
        setStatus('connected');
        reconnectAttemptsRef.current = 0;
        onOpen?.(event);
      };

      wsRef.current.onclose = (event) => {
        setStatus('disconnected');
        onClose?.(event);

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
          const syncData: SyncData = JSON.parse(event.data);
          setData(syncData);
          onMessage?.(syncData);
        } catch (error) {
          console.error('Failed to parse WebSocket message:', error);
        }
      };

    } catch (error) {
      setLastError('Failed to create WebSocket connection');
      console.error('WebSocket connection error:', error);
    }
  }, [url, onOpen, onClose, onError, onMessage]);

  // Verbindung trennen
  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }

    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }

    setStatus('disconnected');
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
    };
  }, [disconnect]);

  return {
    data,
    status,
    error: lastError,
    connect,
    disconnect,
    reconnect: connect
  };
}

// Alias für Kompatibilität mit bestehendem Code
export function useAutoRefresh(jsonPath?: string, _intervalMs?: number) {
  // Dies ist ein Fallback für Polling-Implementierungen
  // Die Haupt-Implementierung verwendet WebSocket

  const { data, status } = useWebSocket({
    url: 'ws://localhost:5174'
  });

  // Wenn ein spezifischer jsonPath angefordert wird, filtere die Daten
  if (jsonPath && data) {
    // Hier könnte man spezifische Dateien aus den Daten extrahieren
    // Da der WebSocket alle Daten sendet, muss der Client entscheiden was er verwenden möchte
  }

  return {
    data,
    status,
    loading: status === 'connecting',
    error: status === 'disconnected' ? null : undefined
  };
}
