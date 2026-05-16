# Vorce-Pilot: Dokumentation & Anleitung

Vorce-Pilot ist ein leichtgewichtiges Automatisierungssystem, das die Präzision von Makro-Aufzeichnungen mit der Intelligenz von Google Gemini kombiniert.

## 1. Systemaufbau

Das System besteht aus drei Kern-Komponenten:

*   **`vorce_automation.py`**: Enthält die "Hardware-Schnittstelle".
    *   `VorceRecorder`: Zeichnet Maus- und Tastatur-Events in JSON-Dateien auf.
    *   `VorceActions`: Führt Klicks, Tippen und Makro-Wiedergabe aus.
*   **`vorce_pilot.py`**: Das Gehirn. Nutzt Gemini (Vision), um den Bildschirm zu verstehen und Entscheidungen zu treffen.
*   **`CuaAPI-Key`**: Deine Eintrittskarte zur KI (gespeichert in den Windows-Umgebungsvariablen oder der Registry).

## 2. Wo liegen die Screenshots?

**Kurze Antwort:** Aktuell werden sie **nicht** lokal gespeichert.

Die Methode `capture_screen()` macht einen Screenshot direkt in den Arbeitsspeicher (RAM). Dieser wird als PIL-Bild-Objekt an Gemini gesendet und danach sofort verworfen.
*   **Vorteil:** Keine Festplattenbelastung, hohe Geschwindigkeit, maximale Privatsphäre.
*   **Debug-Modus:** Wenn du sie speichern willst (z.B. zur Fehlersuche), kannst du `img.save("debug.png")` in `vorce_pilot.py` einfügen.

## 3. Anleitung: Aufzeichnung (Makros)

Nutze Aufzeichnungen für Schritte, die immer identisch sind (z.B. Login, Programmstart).

1.  Starte den Recorder: `python vorce_automation.py`.
2.  Führe die Aktionen aus.
3.  Drücke **ESC**, um die Aufnahme zu beenden.
4.  Die Datei `test_macro.json` wird erstellt.

## 4. Anleitung: Automatisierter UI-Test

Ein smarter UI-Test kombiniert Makros (für den Weg) und KI (für die Prüfung).

### Beispiel-Ablauf:
1.  **Makro:** Startet deine App und navigiert zum Dashboard.
2.  **KI (Pilot):** Prüft, ob das Dashboard korrekt aussieht (z.B. "Ist der 'Logout'-Button sichtbar?").

### Beispiel-Skript (`my_ui_test.py`):
```python
from vorce_automation import VorceActions
from vorce_pilot import VorcePilot

actions = VorceActions()
pilot = VorcePilot()

# Schritt 1: Makro abspielen (Navigation)
actions.play_macro("dashboard_nav.json")

# Schritt 2: KI-Check
pilot.think_and_act("Prüfe ob die Fehlermeldung 'Login fehlgeschlagen' erscheint. Wenn ja, klicke auf 'Abbrechen'.")
```

## 5. Einrichtung & Nutzung

### API-Key setzen (Windows):
Öffne PowerShell als Administrator:
```powershell
setx CuaAPI-Key "DEIN_KEY" /M
```
*(Das /M setzt es systemweit, falls du es nur für dich willst, lass /M weg).*

### Den Piloten starten:
```bash
python vorce_pilot.py
```
Gib dann dein Ziel ein, z.B.: *"Suche in Windows nach dem Taschenrechner, öffne ihn und rechne 5 + 5."*

---

**Tipp:** Nutze Gemini **1.5 Flash** (Standard in `vorce_pilot.py`), da es für UI-Erkennung optimiert ist und fast keine Latenz hat.
