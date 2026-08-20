const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const A2AServer = require('./A2AServer');

class WebSocketServer {
    constructor(host = 'localhost', port = 5174, a2aPort = 5175) {
        this.host = host;
        this.port = port;
        this.a2aPort = a2aPort;
        this.server = null;
        this.clients = new Set();
        this.a2aServer = null;
        this.dbPath = path.join(__dirname, '../../../var/db');
        this.runStatesPath = path.join(__dirname, '../../../var/run-states');
        this.logPath = path.join(__dirname, '../../../var/log/autopilot.log');
    }

    start() {
        this.server = new WebSocket.Server({
            host: this.host,
            port: this.port,
            clientTracking: true
        });

        this.server.on('connection', (ws, req) => {
            console.log(`[WebSocket] Neue Verbindung von ${req.socket.remoteAddress}`);
            this.clients.add(ws);

            ws.on('close', () => {
                console.log(`[WebSocket] Verbindung geschlossen ${req.socket.remoteAddress}`);
                this.clients.delete(ws);
            });

            ws.on('error', (error) => {
                console.error(`[WebSocket] Fehler:`, error);
                this.clients.delete(ws);
            });

            // Sende Initialstatus
            this.sendToClient(ws, {
                type: 'connection-established',
                timestamp: new Date().toISOString()
            });
        });

        this.server.on('error', (error) => {
            console.error(`[WebSocket] Server Fehler:`, error);
        });

        console.log(`[WebSocket] Server gestartet auf ws://${this.host}:${this.port}`);

        // ── Start A2A Express server ──
        this._startA2AServer();
    }

    /**
     * Start the A2A Express server (non-blocking if express is missing).
     */
    _startA2AServer() {
        try {
            this.a2aServer = new A2AServer(this, this.a2aPort);
            this.a2aServer.start();
        } catch (err) {
            console.error('[WebSocket] A2A-Server-Start fehlgeschlagen:', err.message);
        }
    }

    sendToClient(client, data) {
        if (client.readyState === WebSocket.OPEN) {
            try {
                client.send(JSON.stringify(data));
            } catch (error) {
                console.error(`[WebSocket] Fehler beim Senden:`, error);
            }
        }
    }

    broadcast(data, excludeClient = null) {
        this.clients.forEach(client => {
            if (client !== excludeClient) {
                this.sendToClient(client, data);
            }
        });
    }

    // Liest die neuesten Zeilen aus der Log-Datei
    readLatestLogLines(count = 50) {
        try {
            if (!fs.existsSync(this.logPath)) {
                return [];
            }

            const stats = fs.statSync(this.logPath);
            if (stats.size === 0) {
                return [];
            }

            const buffer = Buffer.alloc(Math.min(stats.size, 64 * 1024)); // Max 64KB
            const fd = fs.openSync(this.logPath, 'r');
            const position = stats.size - buffer.length;

            fs.readSync(fd, buffer, 0, buffer.length, position);
            fs.closeSync(fd);

            const content = buffer.toString('utf-8');
            const lines = content.split('\n').filter(line => line.trim());

            // Entferne die Zeile, die möglicherweise abgeschnitten wurde
            if (position > 0) {
                lines.shift();
            }

            return lines.slice(-count).map(line => ({
                line,
                timestamp: new Date().toISOString()
            }));
        } catch (error) {
            console.error('[WebSocket] Fehler beim Lesen der Log-Datei:', error);
            return [];
        }
    }

    // Sendet ein Update für eine spezifische Datei
    sendFileUpdate(filePath, eventType) {
        const relativePath = path.relative(path.join(__dirname, '../../../var'), filePath);
        const stats = fs.existsSync(filePath) ? fs.statSync(filePath) : null;

        const update = {
            type: 'file-update',
            path: relativePath,
            eventType: eventType,
            timestamp: new Date().toISOString(),
            data: stats ? {
                size: stats.size,
                modified: stats.mtime.toISOString(),
                exists: true
            } : {
                exists: false
            }
        };

        this.broadcast(update);
    }

    // Sendet Log-Updates
    sendLogUpdate() {
        const logs = this.readLatestLogLines(50);
        this.broadcast({
            type: 'log-update',
            logs: logs,
            timestamp: new Date().toISOString()
        });
    }

    // Simuliere die Überwachung von Dateien (in einer echten Implementation würden wir fs.watch verwenden)
    startFileMonitoring() {
        // Periodische Überprüfung der wichtigsten Dateien
        setInterval(() => {
            // Überprüfe DB-Dateien
            if (fs.existsSync(this.dbPath)) {
                const files = fs.readdirSync(this.dbPath);
                files.forEach(file => {
                    const filePath = path.join(this.dbPath, file);
                    const stats = fs.statSync(filePath);
                    // Sende Update wenn die Datei in den letzten 5 Sekunden geändert wurde
                    if (stats.mtime > new Date(Date.now() - 5000)) {
                        this.sendFileUpdate(filePath, 'changed');
                    }
                });
            }

            // Überprüfe Run-State-Dateien
            if (fs.existsSync(this.runStatesPath)) {
                const files = fs.readdirSync(this.runStatesPath);
                files.forEach(file => {
                    const filePath = path.join(this.runStatesPath, file);
                    const stats = fs.statSync(filePath);
                    if (stats.mtime > new Date(Date.now() - 5000)) {
                        this.sendFileUpdate(filePath, 'changed');
                    }
                });
            }
        }, 2000); // Alle 2 Sekunden prüfen

        // Log-Updates alle 5 Sekunden
        setInterval(() => {
            this.sendLogUpdate();
        }, 5000);
    }

    stop() {
        if (this.a2aServer) {
            this.a2aServer.stop();
        }
        if (this.server) {
            this.server.close();
            this.clients.forEach(client => {
                client.close();
            });
            this.clients.clear();
            console.log('[WebSocket] Server gestoppt');
        }
    }
}

// Export for reuse (e.g. by tests)
module.exports = WebSocketServer;

// Starte den Server
const server = new WebSocketServer(process.argv[2] || 'localhost', parseInt(process.argv[3]) || 5174);
server.start();
server.startFileMonitoring();

// Handle graceful shutdown
process.on('SIGINT', () => {
    console.log('\n[WebSocket] Shutdown signal erhalten...');
    server.stop();
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\n[WebSocket] Shutdown signal erhalten...');
    server.stop();
    process.exit(0);
});