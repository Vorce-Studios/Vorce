# Vorce-Autopilot 3.0 - System-Dokumentation (V3)

## 1. Architektur-Übersicht
Vorce-Autopilot 3.0 ist ein modulares, datengetriebenes Framework zur Orchestrierung von KI-Agenten. Es folgt einer strikten hierarchischen Struktur:
**Main-Run** -> **Router** -> **Sub-Run** -> **Part-Run**.

### Komponenten:
- **`autopilot.ps1`**: Der schlanke Wächter-Loop. Er initialisiert das System und triggert in festen Intervallen den Orchestrator.
- **`Vorce-Orchestrator.ps1`**: Das Herzstück. Er verwaltet die Hierarchie, steuert die Parallelität der Part-Runs und sorgt für die Synchronisation mit externen Systemen.
- **`Start-Autopilot.ps1`**: Bootstrapper für die Infrastruktur (Vite-Dashboard, Sync-Dienste).

## 2. Daten- & Kommunikationsfluss
- **Isolation**: Ausführbarer Code (`src/`) ist strikt von veränderlichen Daten (`var/`) getrennt.
- **Run-States**: Jeder Prozessschritt speichert sein Ergebnis als standardisiertes JSON in `var/run-states/`.
- **Global State**: Der Gesamtzustand wird in `var/db/global-state.json` verwaltet und dient als primäre Datenquelle für das Dashboard.

## 3. GitHub & Dashboard Synchronisation
Alle Statusänderungen innerhalb der Suite werden automatisch bidirektional synchronisiert:
1. **GitHub Project Sync**: Bei jedem Start und Abschluss eines Main-Runs (oder wichtiger Sub-Runs) kommuniziert der Orchestrator via `ProjectManager.ps1` mit dem @Vorce Project Board auf GitHub.
2. **Dashboard Sync**: Das Dashboard-Backend (`vite.config.ts`) überwacht die Dateien in `var/db/` und `var/run-states/`. Sobald der Orchestrator einen State speichert, aktualisiert sich das Dashboard in Echtzeit.

## 4. Betrieb & Terminal-Ausgabe
Der neue Standard für Terminal-Ausgaben nutzt das `StatusPrinter.ps1` Modul:
- **Header/Footer**: Klare Abgrenzung der Runs.
- **Icons & Farben**: Sofortige visuelle Erfassung des Status (✅ OK, ⚠️ Warnung, ❌ Fehler).
- **Fortschritt**: Anzeige der abgearbeiteten Teile (z. B. "Sub-Run 2/5").

## 5. Parallelität
Innerhalb eines Sub-Runs werden Part-Runs parallel ausgeführt. Die maximale Anzahl gleichzeitiger Jobs ist über den Orchestrator konfigurierbar, um Systemressourcen und API-Quoten zu schonen. Jeder Sub-Run endet mit einem Aggregations-Schritt, der die parallelen Ergebnisse konsolidiert.
