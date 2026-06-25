// useA2ALive.ts (Vorce 3.0 A2A)
// React Hook für A2A-Echtzeitnachrichten via WebSocket

import { useCallback, useRef, useState } from 'react';
import { useWebSocketEnhanced } from './useWebSocketEnhanced';

// ── Types ──

export interface A2AMessage {
  id: string;
  type: 'TaskProgress' | 'CritiqueFeedback' | 'a2a.message' | string;
  source: string;
  target: string;
  payload: Record<string, unknown>;
  timestamp: string;
}

interface A2AWebSocketEvent {
  type: 'a2a_message';
  payload: {
    jsonrpc: string;
    id: string | null;
    method: string;
    params: Record<string, unknown>;
    target: string;
    source: string;
  };
  timestamp: string;
}

interface UseA2ALiveOptions {
  maxMessages?: number;
  filterTarget?: string;
}

interface UseA2ALiveReturn {
  messages: A2AMessage[];
  unreadCount: number;
  markAllRead: () => void;
  clearMessages: () => void;
  connectionStatus: 'connected' | 'disconnected' | 'reconnecting';
}

/**
 * Hook for consuming A2A live messages from the WebSocket.
 * Follows the same pattern as useLiveLog / useFileUpdates.
 */
export function useA2ALive({
  maxMessages = 100,
  filterTarget
}: UseA2ALiveOptions = {}): UseA2ALiveReturn {
  const [messages, setMessages] = useState<A2AMessage[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const idCounterRef = useRef(0);

  const handleMessage = useCallback((message: unknown) => {
    const msg = message as Record<string, unknown>;

    // Only process a2a_message events
    if (msg?.type === 'a2a_message') {
      const event = msg as unknown as A2AWebSocketEvent;
      const payload = event.payload || {};

      // Apply target filter if set
      if (filterTarget && payload.target?.toLowerCase() !== filterTarget.toLowerCase()) {
        return;
      }

      idCounterRef.current += 1;
      const a2aMsg: A2AMessage = {
        id: payload.id || 'a2a-' + idCounterRef.current,
        type: payload.method === 'tasks/task_progress'
          ? 'TaskProgress'
          : payload.method === 'tasks/task_critique'
            ? 'CritiqueFeedback'
            : payload.method || 'a2a.message',
        source: payload.source || 'unknown',
        target: payload.target || 'Dashboard',
        payload: payload.params || {},
        timestamp: event.timestamp || new Date().toISOString()
      };

      setMessages(prev => {
        const next = [a2aMsg, ...prev];
        return next.slice(0, maxMessages);
      });
      setUnreadCount(prev => prev + 1);
    }
  }, [filterTarget, maxMessages]);

  const { connectionStatus } = useWebSocketEnhanced({
    onMessage: handleMessage
  });

  // Reset unread when messages change externally (e.g. clear)
  const markAllRead = useCallback(() => {
    setUnreadCount(0);
  }, []);

  const clearMessages = useCallback(() => {
    setMessages([]);
    setUnreadCount(0);
  }, []);

  return {
    messages,
    unreadCount,
    markAllRead,
    clearMessages,
    connectionStatus
  };
}
