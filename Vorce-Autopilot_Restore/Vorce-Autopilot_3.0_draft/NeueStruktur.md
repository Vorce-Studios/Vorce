Neue Verzeichnisstruktur (Vorce-Autopilot_3.0)

```
Vorce-Autopilot_3.0/
├── autopilot.ps1              # Haupt-Loop (MAIN-RUN Trigger)
├── Start-Autopilot.ps1        # Dashboard + Backend Start
├── src/
│   ├── lib/                   # Bibliotheken (state-manager etc.)
│   ├── orchestrator/          # Orchestrator-Run.ps1 (Orchestrierer)
│   ├── runs/
│   │   ├── MAIN-RUNS/          # MAIN-RUNS (MAIN-RUN-01_Planning, MAIN-RUN-02_Check&Doing, MAIN-RUN-03_QA-Audit, MAIN-RUN-04_Autopilot-Optimizer, MAIN-RUN-05_MemoryOptimization
│   │       └── ROUTER/                 # Router-Skripte (dynamische SUB-RUN-Entscheidung, je nach aktuellem Bedarf und Status entscheidet der Router nach bestimmten anpassbaren Kriterien in jedem MAIN-RUN welche SUB-RUNS benötigt werden und sinnvoll sind)
│   │           └── SUB-RUNS/           # SUB-RUN-01...06 (jeder Main-Run verfügt über diverse Sub-Runs, ein Sub-Run sind bestimmte Aufgaben die in der Regel auf mehrere PART-RUNS aufgesplittet sind um Tokensparend und effizent eine einzele Teilaufgabe zu erledigen und die Ergebnise in einer .json zu speichern)
│   │               └── PART-RUNS/      # einzele Teilaufgaben von einem SUB-RUN (jeder PART-RUN muss ein Ergebniss in einer .json speichern, die Teilergebnisse werden am Ende des SUB-RUN zusammengeführt verarbeitet)
│   └── tools/                          # alle Hintergrund Skripte die automatisch laufen wie z.B. Jules Session Monitoring, Github Sync usw.
│
├── web/  
│   └── Dashboard/              # alle Dateien des Dashboard Webfrontend (inkl. Unterordnern mit einer Struktur und eindeutigen + einheitlichen Namen wo man erkennt für die Dateien jeweils sind)
│
└── var/
    ├── config/
    │   └── autopilot-config.json  # Konfiguration (Intervalle, Labels)
	├── prompts/                   # Systemprompts (inkl. Unterordnern mit der Run Struktur und eindeutigen + einheitlichen Namen wo man erkennt für was der Prompt jeweils ist
    ├── db/                        # active-sessions.json, pull-requests.json
    ├── log/                       # autopilot_14-06-2026_08-30.log (bei jedem Start wird eine neue Log Datei begonnen, es sollen immer nur die letzten 10 Logs aufbewart werden)  
    ├── run-states/            # run-state.json Files
    └── tmp/                   # TMP-Files
