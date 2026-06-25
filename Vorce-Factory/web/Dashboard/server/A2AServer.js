// A2AServer.js (Vorce 3.0 A2A)
// Express-based A2A message relay for Agent-to-Agent communication
// Integrates with WebSocketServer to broadcast to dashboard clients

const fs = require('fs');
const path = require('path');

// Try to load @a2a-js/sdk gracefully — if not installed, use a fallback
let a2aSdk = null;
try {
  a2aSdk = require('@a2a-js/sdk');
  console.log('[A2AServer] @a2a-js/sdk geladen');
} catch {
  console.log('[A2AServer] @a2a-js/sdk nicht installiert — verwende Fallback');
}

// ── CEO messages file ──
const CEO_MESSAGES_FILE = path.join(__dirname, '../../../var/tmp/ceo-messages.json');

/**
 * Ensure the CEO messages file exists and return its content.
 */
function readCeoMessages() {
  try {
    if (!fs.existsSync(CEO_MESSAGES_FILE)) {
      fs.writeFileSync(CEO_MESSAGES_FILE, JSON.stringify({ messages: [] }), 'utf-8');
      return { messages: [] };
    }
    const raw = fs.readFileSync(CEO_MESSAGES_FILE, 'utf-8');
    return JSON.parse(raw);
  } catch (err) {
    console.error('[A2AServer] Fehler beim Lesen der CEO-Nachrichten:', err.message);
    return { messages: [] };
  }
}
/**
 * Append a message to the CEO's task queue file.
 */
function appendCeoMessage(payload) {
  try {
    const store = readCeoMessages();
    store.messages.push({
      ...payload,
      received_at: new Date().toISOString()
    });
    // Keep only the last 200 messages
    if (store.messages.length > 200) {
      store.messages = store.messages.slice(-200);
    }
    fs.writeFileSync(CEO_MESSAGES_FILE, JSON.stringify(store, null, 2), 'utf-8');
    console.log('[A2AServer] CEO-Nachricht gespeichert —', payload.method || 'unknown');
    return true;
  } catch (err) {
    console.error('[A2AServer] Fehler beim Speichern der CEO-Nachricht:', err.message);
    return false;
  }
}

/**
 * Normalise a JSON-RPC 2.0 payload into a uniform A2A envelope.
 */
function normaliseA2APayload(body) {
  // Already has jsonrpc field
  if (body.jsonrpc === '2.0') {
    return {
      jsonrpc: '2.0',
      id: body.id || null,
      method: body.method || 'unknown',
      params: body.params || {},
      target: body.target || 'Dashboard',
      source: body.source || 'unknown'
    };
  }

  // Plain object — wrap as notification
  return {
    jsonrpc: '2.0',
    id: null,
    method: body.method || 'a2a.message',
    params: body.params || body,
    target: body.target || 'Dashboard',
    source: body.source || 'unknown'
  };
}

class A2AServer {
  /**
   * @param {import('./WebSocketServer')} wsServer  Reference to the running WebSocketServer
   * @param {number} port  Port for the Express A2A endpoint (default 5175)
   */
  constructor(wsServer, port = 5175) {
    this.wsServer = wsServer;
    this.port = port;
    this.app = null;
    this.httpServer = null;
  }

  /**
   * Start the Express server and register the POST /api/a2a route.
   */
  start() {
    let express;
    try {
      express = require('express');
    } catch {
      console.error('[A2AServer] Express ist nicht installiert');
      console.log('[A2AServer] Starte ohne Express — A2A-Endpoint deaktiviert');
      return;
    }

    this.app = express();
    this.app.use(express.json());

    this.app.post('/api/a2a', (req, res) => {
      try {
        const body = req.body || {};
        const payload = normaliseA2APayload(body);
        console.log('[A2AServer] A2A empfangen:', payload.method, '\u2192', payload.target);

        let enrichedPayload = payload;
        if (a2aSdk && typeof a2aSdk.createMessage === 'function') {
          try {
            enrichedPayload = a2aSdk.createMessage({
              jsonrpc: payload.jsonrpc,
              method: payload.method,
              params: payload.params
            });
            enrichedPayload.target = payload.target;
            enrichedPayload.source = payload.source;
          } catch (sdkErr) {
            console.warn('[A2AServer] @a2a-js/sdk Fehler:', sdkErr.message);
          }
        }

        const target = (payload.target || 'Dashboard').toLowerCase();

        if (target === 'dashboard') {
          this.wsServer.broadcast({
            type: 'a2a_message',
            payload: enrichedPayload,
            timestamp: new Date().toISOString()
          });
        } else if (target === 'ceo') {
          appendCeoMessage(enrichedPayload);
        } else {
          this.wsServer.broadcast({
            type: 'a2a_message',
            payload: { ...enrichedPayload, target, _fallback: true },
            timestamp: new Date().toISOString()
          });
          console.log('[A2AServer] Unbekanntes Ziel "' + target + '" — an Dashboard weitergeleitet');
        }

        res.status(200).json({
          jsonrpc: '2.0',
          id: payload.id,
          result: { status: 'accepted', target }
        });
      } catch (err) {
        console.error('[A2AServer] Fehler:', err);
        res.status(500).json({
          jsonrpc: '2.0',
          id: req.body?.id || null,
          error: { code: -32603, message: 'Internal error', data: err.message }
        });
      }
    });

    this.app.get('/api/a2a/health', (_req, res) => {
      res.json({ status: 'ok', sdk: !!a2aSdk, port: this.port });
    });

    this.httpServer = this.app.listen(this.port, () => {
      console.log('[A2AServer] A2A-Endpoint auf http://localhost:' + this.port + '/api/a2a');
      console.log('[A2AServer]   POST /api/a2a  — A2A-JSON-RPC');
      console.log('[A2AServer]   GET  /api/a2a/health — Health-Check');
      if (a2aSdk) {
        console.log('[A2AServer]   @a2a-js/sdk aktiv');
      } else {
        console.log('[A2AServer]   @a2a-js/sdk NICHT aktiv');
      }
    });

    this.httpServer.on('error', (err) => {
      console.error('[A2AServer] Server-Fehler:', err.message);
    });
  }

  stop() {
    if (this.httpServer) {
      this.httpServer.close();
      this.httpServer = null;
      console.log('[A2AServer] Gestoppt');
    }
  }
}

module.exports = A2AServer;
