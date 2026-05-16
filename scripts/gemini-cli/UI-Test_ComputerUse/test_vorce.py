import os
import sys
from vorce_automation import VorceActions, VorceRecorder
from vorce_pilot import VorcePilot

def test_environment_and_basics():
    print("--- VORCE TEST SUITE ---")
    
    # 1. Check API Key through the pilot's logic
    from vorce_pilot import get_api_key
    api_key = get_api_key()
    if api_key:
        print(f"[OK] Variable 'CuaAPI-Key' gefunden (Länge: {len(api_key)}).")
    else:
        print(f"[FAIL] Variable 'CuaAPI-Key' fehlt weiterhin!")

    # 2. Test Screenshot Capability
    try:
        pilot = VorcePilot()
        img = pilot.capture_screen()
        print(f"[OK] Screenshot erfolgreich ({img.width}x{img.height}).")
    except Exception as e:
        print(f"[FAIL] Screenshot-Fehler: {e}")

    # 3. Test Automation Basics (Non-Destructive)
    try:
        actions = VorceActions()
        print(f"[TEST] Bewege Maus kurz in die Mitte...")
        # Move mouse without clicking to verify automation link
        import pyautogui
        pyautogui.moveTo(actions.screen_width // 2, actions.screen_height // 2, duration=0.5)
        print(f"[OK] Maus-Steuerung funktioniert.")
    except Exception as e:
        print(f"[FAIL] Automatisierungs-Fehler: {e}")

    print("\n--- TEST ABGESCHLOSSEN ---")

if __name__ == "__main__":
    test_environment_and_basics()
