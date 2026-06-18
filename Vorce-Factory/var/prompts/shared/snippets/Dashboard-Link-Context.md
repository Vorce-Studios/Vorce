# Dashboard-Link Context

## System Status
- **Dashboard URL**: http://localhost:5173
- **WebSocket**: ws://localhost:5174
- **Last Sync**: [[DASHBOARD_LAST_SYNC]]
- **Connection Status**: [[DASHBOARD_CONNECTION_STATUS]]

## Run State Links
- **Main Run States**: /var/run-states/main-*.json
- **Sub Run States**: /var/run-states/sub-*.json  
- **Part Run States**: /var/run-states/part-*.json

## Database Locations
- **Registry**: /var/db/registry.json
- **Session Data**: /var/db/sessions.json
- **Live Logs**: /var/log/autopilot.log

## API Endpoints
- **Run Control**: POST /api/run-control
- **Trigger Main Run**: POST /api/trigger-main-run
- **Clear Alerts**: POST /api/clear-alerts
- **Live Log Stream**: GET /var/log/autopilot.log

## Real-time Features
- WebSocket Updates: Alle 2 Sekunden für Dateiänderungen
- Log Updates: Alle 5 Sekunden für neue Log-Einträge
- Auto-reconnect: Automatische Neuverbindung nach Verbindungsabbruch