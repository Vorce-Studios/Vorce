# Vorce-Autopilot 3.0 - RADIKALER REFACTORING PLAN (Optimierte Architektur)

## 1. Architektonisches Leitbild
Weg von der "Skript-Sammlung" hin zu einem **modularen Framework**.
- **Isolation:** Jede Ebene (Main/Sub/Part) kennt nur ihre unmittelbaren Nachbarn.
- **Datengetrieben:** Kommunikation erfolgt ausschließlich über standardisierte JSON-States in `var/run-states/`.
- **Zero-Legacy-Policy:** Dateien aus V1/V2 werden **nicht** 1:1 übernommen. Stattdessen wird die benötigte Kernlogik (z.B. API-Aufrufe) extrahiert und in neue, saubere Funktions-Module integriert.

## 2. Optimierte Verzeichnisstruktur
```text
Vorce-Autopilot_3.0/
├── autopilot.ps1                   # Schlanker Einstiegspunkt (Init -> Trigger Orchestrator)
├── Start-Autopilot.ps1             # Infrastruktur-Bootstrapper (Dashboard, Hintergrunddienste)
├── src/
│   ├── lib/                        # Hochgradig bereinigte Kern-Funktionen (Common Utils)
│   │   ├── StateManager.ps1        # Zustandsverwaltung (Global & Run-Local)
│   │   ├── ApiClient.ps1           # Basis für Github/Jules (reiner REST-Client)
│   │   └── QuotaGuard.ps1          # Quoten-Prüfung vor jedem Agent-Run
│   ├── orchestrator/
│   │   └── Vorce-Orchestrator.ps1  # Das Gehirn: Steuert den Ablauf (lädt Runs, fragt Router)
│   ├── runs/
│   │   ├── MAIN-RUN-01_Planning/
│   │   │   ├── Planning-Router.ps1 # Entscheidet dynamisch über benötigte Sub-Runs
│   │   │   ├── SUB-RUNS/           # Logische Aufgabenpakete (z.B. Triage)
│   │   │   └── PART-RUNS/          # Atomare Agent-Aufrufe (erzeugen JSON-Output)
│   │   └── MAIN-RUN-02_CheckDoing/ ...
│   └── tools/                      # Autonome Hintergrund-Dienste (Sync, Health-Monitor)
├── web/Dashboard/                  # Modernes Frontend (Vite/React), bereinigt von Pfad-Hardcodes
└── var/                            # STRIKTE TRENNUNG: Nur hier landen Schreibzugriffe
    ├── config/                     # Statische JSON-Configs
    ├── prompts/                    # System-Prompts, exakt nach Run-Struktur sortiert
    ├── db/                         # Persistente Datenbank-JSONs
    ├── log/                        # Rolling Logs (max. 10 Dateien)
    ├── run-states/                 # Aktuelle Run-Hierarchie (JSON-Handoffs)
    └── tmp/                        # Temporäre Arbeitsdaten
```

## 3. Umsetzungs-Phasen & Test-Checkpoints

### Phase 1: Die "Leere Hülle" (Struktur & Boot)
- [ ] Aufbau der Ordnerstruktur (Erledigt).
- [ ] **Neuschreiben** von `Start-Autopilot.ps1`: Nur Infrastruktur-Start, robuster Health-Check für das Dashboard.
- [ ] **Neuschreiben** von `autopilot.ps1`: Nur Initialisierung des Global-States und Aufruf des Orchestrators.
- **Checkpoint 1:** Skripte starten ohne Fehler, Dashboard ist erreichbar, leeres Logfile in `var/log/` wird erstellt.

### Phase 2: Die Engine (Orchestrator & State)
- [ ] **Neuentwicklung** `StateManager.ps1`: Fokus auf Thread-Sicherheit und sauberes JSON-Mapping in `var/run-states/`.
- [ ] **Entwicklung** `Vorce-Orchestrator.ps1`: Implementierung der Hierarchie-Logik (Main -> Router -> Sub -> Part).
- [ ] Erstellen eines **Test-Runs** (`MAIN-RUN-00_Test`): Ein einfacher Ablauf, der nur "Hello World" in einen Run-State schreibt.
- **Checkpoint 2:** Der Orchestrator kann den Test-Run erfolgreich durchlaufen und hinterlässt eine korrekte JSON-Spur in `var/run-states/`.

### Phase 3: Die Kommunikatoren (Lib-Migration)
- [ ] Extraktion der API-Logik aus den alten `jules-client.ps1` und `github-client.ps1`.
- [ ] Zusammenführung in einen modularen `ApiClient.ps1` in `src/lib/`.
- [ ] Integration der Quoten-Logik (stark vereinfacht und robuster).
- **Checkpoint 3:** Ein kleiner Test-Part-Run kann erfolgreich einen "Ping" an die Github-API oder Jules-API senden.

### Phase 4: Die produktiven Runs (Migration mit Substanz)
- [ ] Schrittweiser Aufbau von `MAIN-RUN-01_Planning`.
- [ ] Erstellen der **Stub-Router**: Erstmal fest definierte Pfade, um die Stabilität der neuen Part-Runs zu prüfen.
- [ ] Implementierung der Aggregations-Logik: Sub-Runs sammeln die Part-Run-Ergebnisse ein.
- **Checkpoint 4:** Ein vollständiger Planning-Lauf wird simuliert (Dry-Run), Quoten werden korrekt berechnet und der State wird persistiert.

### Phase 5: Polishing & Dynamik
- [ ] Aktivierung der dynamischen Router-Logik (Decision Making).
- [ ] Finales Aufräumen der Dashboard-Anbindung an die neuen `var/db/` Pfade.
- [ ] Implementierung der Log-Rotation (max. 10 Files).

## 4. Deine Entscheidungspunkte (Aktualisiert)
- **Parallelität:** Part-Runs laufen **parallel** innerhalb eines Sub-Runs. Der Orchestrator steuert eine einstellbare maximale Anzahl an gleichzeitigen Jobs.
- **Aggregation:**
  - Jeder Sub-Run hat einen finalen **Aggregation-Part-Run**, der erst startet, wenn alle anderen fertig sind. Er mergt die Teil-JSONs zu einem Sub-Run-Ergebnis.
  - Jeder Main-Run hat eine finale **Main-Aggregation**, die die Sub-Run-Ergebnisse konsolidiert.
- **Prompts:** Ablage als `.md` Dateien in einer logischen Ordnerhierarchie (`var/prompts/MAIN-RUN/SUB-RUN/PART-RUN.md`), um volle Editierbarkeit über das Dashboard zu gewährleisten.
- **Terminal-Output Standard:**
  - **Eindeutigkeit:** Klare Trennung durch visuelle Divider (Header/Footer für jeden Run).
  - **Status-Indikatoren:** Verwendung von Icons (vortäuschen über Unicode/Farben) und Fortschrittsanzeigen (z.B. "Part 2/5").
  - **Zeitstempel:** Jeder Schritt wird mit exakter Zeit und Dauer geloggt.
  - **Transparenz:** Vor jedem Agent-Call wird der verwendete Provider und das Quoten-Limit angezeigt.

---
## 5. Implementierungs-Details Phase 1 (Checkpoint 1)
### 5.1 Neuentwicklung `Start-Autopilot.ps1`
- Startet nur das Dashboard (Vite) und Sync-Tools.
- Robuster Health-Check (Ping auf Port 5173).
- Kein Legacy-Code von V1/V2.

### 5.2 Neuentwicklung `autopilot.ps1`
- Schlanker Loop.
- Rolling Log Logik (behält nur die letzten 10 Files).
- Initialisiert den `GlobalState` in `var/db/`.
