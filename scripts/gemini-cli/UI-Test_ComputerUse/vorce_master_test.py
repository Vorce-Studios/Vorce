import time
import pygetwindow as gw
from vorce_pilot import VorcePilot
from vorce_automation import VorceActions

def wait_for_vorce_window(timeout=300):
    """Wartet bis ein Fenster mit 'Vorce' im Titel erscheint."""
    print(f"Warte auf Vorce-Fenster (Timeout: {timeout}s)...")
    start_time = time.time()
    while time.time() - start_time < timeout:
        windows = gw.getWindowsWithTitle('Vorce')
        if windows:
            # Zusätzlicher Puffer, damit die UI wirklich gezeichnet ist
            print("Vorce-Fenster gefunden! Warte 5s auf UI-Initialisierung...")
            time.sleep(5)
            return True
        time.sleep(2)
    return False

def run_complex_vorce_test():
    pilot = VorcePilot()
    actions = VorceActions()
    
    print("--- STARTE KOMPLEXEN VORCE APP-TEST ---")
    
    # 1. Vorce Kompilieren und Starten
    print("\n[Schritt 1] Starte Vorce Kompilierung & Launch...")
    import subprocess
    import os
    
    batch_path = os.path.join("scripts", "vorce", "run-vorce-Full.bat")
    # Wir nutzen 'start', um das Batch-Skript in einem eigenen Fenster laufen zu lassen (für Cargo Output)
    subprocess.Popen(f"start cmd /c {batch_path}", shell=True)
    
    # Jetzt warten wir, bis das Fenster tatsächlich erscheint
    if not wait_for_vorce_window():
        print("FEHLER: Vorce wurde nicht rechtzeitig gestartet. Abbruch.")
        return
    
    # 2. Einstellungen öffnen und schließen
    print("\n[Schritt 2] Einstellungen testen...")
    pilot.think_and_act("Finde das Zahnrad-Icon oder den Button 'Einstellungen', klicke darauf, warte 2 Sekunden und schließe das Fenster wieder.")
    
    # 3. Neues Modul erstellen
    print("\n[Schritt 3] Erstelle neues Modul...")
    pilot.think_and_act("Klicke auf 'Neues Modul' oder das '+'-Icon um ein neues Modul zu erstellen.")
    
    # 4. Video und Effekt laden
    print("\n[Schritt 4] Video und Effekt laden...")
    pilot.think_and_act("Suche die Video-Bibliothek, lade ein beliebiges Video in das neue Modul und wende danach einen Effekt (z.B. 'Mirror' oder 'Edge Detect') darauf an.")
    
    # 5. Output checken
    print("\n[Schritt 5] Output Validierung...")
    pilot.think_and_act("Prüfe ob im Output-Fenster das Video mit dem Effekt abgespielt wird. Wenn alles okay aussieht, beende den Task mit 'done'.")

    print("\n--- TEST-ABLAUF BEENDET ---")

if __name__ == "__main__":
    # Sicherheitshinweis für den User
    print("HINWEIS: Stelle sicher, dass die App 'Vorce' installiert ist.")
    print("Die KI wird versuchen, die UI-Elemente visuell zu finden.")
    time.sleep(2)
    run_complex_vorce_test()
