# Strategie & Betrieb (Management-Summary)

Dieses Dokument bietet einen Überblick über die operative Strategie und den Betrieb des Vorce-Autopiloten 2.0.

## 1. Operative Strategie: "Remediate before Escalate"

Der Autopilot ist darauf ausgelegt, das System mit minimaler User-Intervention stabil zu halten.

### Autonome Selbstheilung

Wenn der **QA-Manager** im Audit-Lauf (`MAIN-RUN-03`) eine Compliance-Verletzung (z.B. falsche Benennung, fehlende Tests, kaputte Sessions) findet:

1. **Analysiert** er das Problem.
2. **Generiert** er einen PowerShell-Befehl zur Behebung.
3. **Führt** den Befehl aus.
4. **Prüft** das Ergebnis erneut.

Erst wenn dieser Zyklus fehlschlägt, wird der User über das Dashboard informiert.

## 2. Rollen im System

- **CEO (Strategie-Instanz):** Agiert proaktiv. Er scannt Issues, priorisiert Aufgaben und delegiert sie an Agenten. Sein Ziel ist der Fortschritt des Projekts.
- **QA-Manager (Sicherheits-Instanz):** Agiert reaktiv und kritisch. Er überwacht den CEO (Deliberation) und die Ergebnisse der Agenten (Audit). Sein Ziel ist die Integrität des Projekts.

## 3. Der Orchestrator-Zyklus

Der Autopilot läuft in einer permanenten Schleife (`autopilot.ps1`) mit folgenden Intervallen:

1. **Planning (~60 min):** CEO plant den nächsten Schritt.
2. **Monitoring (~15 min):** Überprüfung laufender Delegationen (Jules, etc.).
3. **Audit (nach jedem Planning):** QA-Manager prüft Compliance.
4. **Optimizer (nach jedem Planning):** Konsolidierung von Memory und Logs.

## 4. Troubleshooting für den Operator

### Alerts verstehen

Ein Alert im Dashboard bedeutet, dass die autonome Heilung fehlgeschlagen ist.

- **Prüfe die Log-Datei:** `var/log/autopilot-live.log` zeigt die Echtzeit-Vorgänge.
- **Deliberation-Protokolle:** In `var/log/deliberations/` findest du die Details zum Dialog zwischen CEO und QA-Manager bei kritischen Entscheidungen.

### Manuelle Eingriffe

- **Wake-Up Trigger:** Erstelle eine leere Datei `autopilot.wakeup` im Hauptverzeichnis, um die Pause sofort zu beenden und einen neuen Zyklus zu starten.
- **Config-Anpassung:** In `config/autopilot-config.json` können Intervalle und Repository-Filter angepasst werden.

---
*Vorce-Autopilot 2.0 - Leitfaden für den Operator*
