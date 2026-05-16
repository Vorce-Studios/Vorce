import pyautogui
import time
import sys

def normalize_click(x, y):
    """Normalized click helper."""
    try:
        pyautogui.click(x, y)
        return True
    except Exception as e:
        print(f"Error clicking at ({x}, {y}): {e}")
        return False

def record_macro():
    """Stub for macro recording."""
    print("Macro recording not fully implemented yet.")

def playback_macro(macro_data):
    """Stub for macro playback."""
    print("Macro playback not fully implemented yet.")
    for action in macro_data:
        if action['type'] == 'click':
            normalize_click(action['x'], action['y'])
            time.sleep(0.5)

if __name__ == "__main__":
    print("Vorce automation helpers loaded.")
