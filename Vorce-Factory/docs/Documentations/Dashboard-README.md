# Vorce-Factory Dashboard

Das Dashboard liegt unter `web/Dashboard/` und ist eine React/Vite-Anwendung fuer Monitoring, Run-Steuerung, Settings, Workstreams und Reporting.

Wichtige Datenquellen:

- `/active-sessions.json` - Runtime-State, Main-Run-Status, Run-States und Dashboard-State.
- `/run-catalog.json` - kanonischer Katalog aus Config, Run-Ordnern und Prompt-Registry.
- `/autopilot-config.json` - editierbare Systemkonfiguration inklusive Router-Regeln.
- `/registry.json` - Quota-/Provider-Registry.
- `/live-log.json` - aktueller Live-Log-Inhalt.

Start:

```powershell
cd Vorce-Factory/web/Dashboard
npm install
npm run dev
```

Build:

```powershell
npm run build
```

Hinweis: Die Dashboard-Run-Hierarchie muss aus dem kanonischen Katalog plus Router-Decision-State aufgebaut werden. Die alte reine Rekonstruktion aus `run_states` ist nicht ausreichend.
