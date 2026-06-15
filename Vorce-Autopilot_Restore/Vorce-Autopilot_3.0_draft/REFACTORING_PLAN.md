# Vorce-Autopilot 3.0 - Refactoring Plan & Architektur-Analyse

## 1. Analyse des Ist-Zustands
Aktuell liegt im Ordner `Vorce-Autopilot_3.0` ein Stand, der zwar die neuen Komponenten (wie `Invoke-MainRun.ps1`) enthält, aber strukturell sehr unaufgeräumt ist:
- **Flache Root-Struktur:** `config/`, `dashboard/`, `prompts/` liegen direkt im Hauptverzeichnis.
- **Unsauberes State-Management:** Laufzeitdaten (`runtime/`, Run-States) wurden wild mit dem Code gemischt.
- **Verschachtelung der Runs:** Die `MAIN-RUNS` enthalten ihre `SUB-RUNS` direkt in sich, was bei vielen Skripten unübersichtlich wird.
- **Dokumentations-Altlasten:** Es gibt viele alte `.md` Dateien aus V1 und V2, die für Verwirrung sorgen.

## 2. Prüfung & Optimierung der neuen Struktur
Die von dir vorgeschlagene Struktur in `NeueStruktur.md` ist exzellent, da sie strikt zwischen ausführbarem Code (`src/`), Frontend (`web/`) und veränderlichen Daten (`var/`) trennt.

**Architektonische Optimierungsgedanken:**
1. **Verzeichnis-Hierarchie der Runs:** Anstatt `ROUTER` -> `SUB-RUNS` -> `PART-RUNS` als *einen* tief verschachtelten Baum für *alle* Runs anzulegen, ist es modularer, wenn jeder `MAIN-RUN` sein eigenes gekapseltes Verzeichnis hat:
   ```text
   src/runs/MAIN-RUN-01_Planning/
   ├── ROUTER/              # Router-Logik speziell für Planning
   ├── SUB-RUNS/            # Die definierten Sub-Runs
   └── PART-RUNS/           # Die atomaren Teilaufgaben
   ```
   So ist ein `MAIN-RUN` eine vollständig in sich geschlossene Einheit (Micro-Architecture).
2. **Der "Stub"-Router:** Wie von dir gewünscht, werden wir den dynamischen Router im ersten Schritt nur als "Skelett" (Stub) bauen. Er wird aufgerufen, gibt aber vorerst eine fest definierte, hardcodierte Liste an SUB-RUNS zurück. Erst wenn das State-Handling, das Orchestrieren und das Speichern der JSON-Ergebnisse in `var/run-states/` reibungslos klappen, "schalten wir das Gehirn des Routers ein".
3. **Zentrale State-Verwaltung:** Alles, was sich zur Laufzeit ändert, landet rigoros in `var/run-states/`. Keine `.json` Dateien mehr tief im `src/`-Ordner.

## 3. Der Refactoring-Plan (Schritt-für-Schritt)

### Phase 1: Aufräumen & Skelett aufbauen (Strukturierung)
- [ ] Erstellen der neuen Hauptordner (`web/Dashboard`, `src/orchestrator`, `src/tools`, `var/config`, `var/prompts`, `var/run-states`).
- [ ] Verschieben der Dateien (`dashboard` -> `web/Dashboard`, `config` -> `var/config`, `prompts` -> `var/prompts`).
- [ ] Löschen/Archivieren aller irrelevanter alter V1/V2 Dokumentationen und veralteten Skripte im Root.
- [ ] Anpassen von `Start-Autopilot.ps1` und `autopilot.ps1`, sodass sie die neuen Pfade (insb. für das Dashboard und die Logs/Config in `var/`) nutzen.

### Phase 2: Orchestrator & Router-Konzept neu schreiben
- [ ] Erstellen von `src/orchestrator/Orchestrator-Run.ps1` (als sauberer Neuanfang, frei von alten Bugs).
- [ ] Einbau der Logik: Der Orchestrator lädt einen MAIN-RUN, ruft dessen ROUTER auf, erhält eine Liste von SUB-RUNS und führt diese sequentiell oder parallel aus.
- [ ] Implementierung der **Stub-Router** in `src/runs/MAIN-RUNS/.../ROUTER/`. Diese geben zum Start einfach hartkodiert zurück: "Führe Sub-Run 1 und dann Sub-Run 2 aus".
- [ ] Umbau der State-Speicherung: Alle Ergebnisse (`MAIN-RUN-STATE.json`, `SUB-RUN-STATE.json`, Teil-JSONs der PART-RUNS) werden strukturiert unter `var/run-states/` abgelegt.

### Phase 3: Sub-Runs und Part-Runs (Ausführung & JSON-Merge)
- [ ] Neuschreiben der Execution-Logik für `PART-RUNS`. Ein Part-Run bekommt ein klares Ziel, generiert ein JSON und speichert es.
- [ ] Der `SUB-RUN` sammelt nach Ausführung aller seiner `PART-RUNS` deren JSON-Ergebnisse ein, mergt diese (oder aggregiert sie) und meldet das Ergebnis an den Orchestrator zurück.

### Phase 4: Integration & Dry-Run
- [ ] Wir starten `autopilot.ps1` im `-DryRun` Modus (oder mit deaktivierten API-Calls), um zu testen, ob der Orchestrator die Router fragt, die Sub-Runs aufruft und die State-Dateien in `var/run-states/` korrekt anlegt.
- [ ] Fehlerbehebung der Pfade und Logik.

Sobald dieser Plan genehmigt ist, können wir strikt und sauber mit Phase 1 beginnen, ohne uns im alten Code zu verstricken.
