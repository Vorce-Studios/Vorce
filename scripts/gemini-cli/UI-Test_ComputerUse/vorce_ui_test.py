import time
from vorce_automation import VorceActions
from vorce_pilot import VorcePilot

def run_automated_ui_test():
    """
    BEISPIEL FÜR EINEN AUTOMATISIERTEN UI TEST
    Struktur: Setup (Makro) -> Interaktion (KI) -> Validierung (KI)
    """
    
    # Initialisierung
    actions = VorceActions()
    pilot = VorcePilot()
    
    print("--- STARTE AUTOMATISIERTEN TEST ---")
    
    # SCHRITT 1: Setup (Ein Makro abspielen, falls vorhanden)
    # actions.play_macro("app_start.json")
    
    # SCHRITT 2: Dynamische Interaktion via KI
    # Wir geben der KI ein klares Ziel
    test_goal = "Öffne das Startmenü, tippe 'Notepad' und drücke Enter."
    pilot.think_and_act(test_goal)
    
    # Kurze Pause für die App
    time.sleep(2)
    
    # SCHRITT 3: Validierung (Die KI prüft den Zustand)
    validation_goal = "Prüfe ob Notepad offen ist. Wenn ja, tippe 'TEST ERFOLGREICH' und beende den Task."
    pilot.think_and_act(validation_goal)
    
    print("--- TEST-ENDE ---")

if __name__ == "__main__":
    run_automated_ui_test()
