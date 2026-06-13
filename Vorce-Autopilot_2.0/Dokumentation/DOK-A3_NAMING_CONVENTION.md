# VORCE-AUTOPILOT 2.0 – NAMING CONVENTION

## 1. Verzeichnisnamen

| Ebene | Format | Beispiel |
|---|---|---|
| Main-Run | `MAIN-RUN/` | `src/runs/MAIN-RUN/` |
| Router | `ROUTER/` | `src/runs/ROUTER/` |
| Sub-Run | `SUB-RUN/` | `src/runs/SUB-RUN/` |
| Part-Run | `PART-RUN/` | *(Reserviert für zukünftige Nutzung)* |

**Regel:** Verzeichnisnamen sind **UPPER-CASE mit Bindestrichen**. Keine lowercase Duplikate.

---

## 2. Skript-Dateinamen

### Main-Run Skripte
```
MAIN-RUN-{NR}_{Phase}.ps1
```
- `{NR}`: Zweistellige Nummer (01, 02, 03)
- `{Phase}`: PascalCase Phasenname

Beispiele:
- `MAIN-RUN-01_Planning.ps1`
- `MAIN-RUN-02_Monitoring.ps1`
- `MAIN-RUN-03_Audit.ps1`

### Router-Skripte
```
ROUTER_MAIN-RUN-{NR}_{Phase}.ps1
```
Der Name spiegelt exakt den zugehörigen Main-Run wider.

Beispiele:
- `ROUTER_MAIN-RUN-01_Planning.ps1`
- `ROUTER_MAIN-RUN-02_Monitoring.ps1`

### Sub-Run Skripte
```
SUB-RUN-{NR}_MR-{MR-NR}_{Phase}__{Funktion}.ps1
```
- `{NR}`: Zweistellige Sub-Run Nummer innerhalb des Main-Runs
- `MR-{MR-NR}`: Kurzform des zugehörigen Main-Runs
- `{Phase}`: Phasenname
- `__{Funktion}`: Doppelter Unterstrich als Separator, dann die funktionale Beschreibung

Beispiele:
- `SUB-RUN-01_MR-01_Planning__ContextGathering.ps1`
- `SUB-RUN-02_MR-01_Planning__LegacyFallback.ps1`
- `SUB-RUN-01_MR-02_Monitoring__SystemHealthCheck.ps1`

### Part-Run Skripte *(Zukünftig)*
```
PART-RUN-{NR}_SR-{SR-NR}_MR-{MR-NR}_{Phase}__{Funktion}.ps1
```

---

## 3. State-Dateien

| Ebene | Dateiname | Speicherort |
|---|---|---|
| Main-Run | `MAIN-RUN-STATE.json` | `var/run/{MainRunName}/` |
| Sub-Run | `SUB-RUN-STATE.json` | `var/run/{MainRunName}/SUB-RUNS/{SubRunName}/` |
| Part-Run | `PART-RUN-STATE.json` | `...SUB-RUNS/{SubRunName}/PART-RUNS/{PartRunName}/` |

---

## 4. Config-Referenzen (`router_rules`)

In `autopilot-config.json` werden Sub-Runs referenziert mit:

```json
{
  "id": "01",
  "name": "ContextGathering",
  "script": "src/runs/SUB-RUN/SUB-RUN-01_MR-01_Planning__ContextGathering.ps1",
  "enabled": true
}
```

- `id`: Zweistellige Nummer (wird im Runtime-Namen verwendet)
- `name`: Kurzname für Logs und State-Aggregation
- `script`: Relativer Pfad ab Projektroot
- `enabled`: Boolean für Aktivierung/Deaktivierung

---

## 5. Log-Prefixe

| Prefix | Quelle |
|---|---|
| `[ORCHESTRATOR]` | `Invoke-MainRun.ps1` |
| `[ROUTER]` | `ROUTER_*.ps1` |
| `[SUB-RUN]` | `SUB-RUN-*.ps1` |
| `[PART-RUN]` | `PART-RUN-*.ps1` |
| `[LOOP]` | `autopilot.ps1` (Hauptschleife) |
| `[INIT]` | `Start-Autopilot.ps1` |
| `[CONTROL]` | Control Console |
| `[FALLBACK]` | Legacy-Fallback Sub-Runs |

---

## 6. Hinweise zu Windows-Pfadlängen

Die vollständigen Pfade können lang werden:
```
var/run/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_MR-01_Planning__ContextGathering/SUB-RUN-STATE.json
```

**Empfehlungen:**
- Stelle sicher, dass Windows Long Paths aktiviert sind (`HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled = 1`)
- Halte den Projektpfad so kurz wie möglich (z.B. `C:\Vorce\Autopilot\`)
- Bei Problemen: Run-Verzeichnisse können intern gekürzte UUIDs verwenden
