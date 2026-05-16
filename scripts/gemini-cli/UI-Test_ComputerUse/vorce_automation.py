import pyautogui
import time
import os
import json
import subprocess
import sys

def main():
    print("Starting deterministic UI test...")
    # Wait for the window to be visible and get its bounds
    max_wait = 180 # increased wait time to allow for slow startup
    window_found = False
    window_info = None

    for _ in range(max_wait):
        try:
            # Using wmctrl to get window info
            output = subprocess.check_output(['wmctrl', '-lG']).decode('utf-8')
            for line in output.split('\n'):
                if 'Vorce' in line:
                    parts = line.split()
                    if len(parts) >= 6:
                        x = int(parts[2])
                        y = int(parts[3])
                        w = int(parts[4])
                        h = int(parts[5])
                        window_info = (x, y, w, h)
                        window_found = True
                        print(f"Found Vorce window at {x}, {y} with size {w}x{h}")
                        break
        except Exception as e:
            pass

        if window_found:
            break
        if _ % 10 == 0:
            print(f"Waiting for Vorce window... ({_}/{max_wait})")
        time.sleep(1)

    if not window_found:
        print("Error: Could not find Vorce window.")
        sys.exit(1)

    # Initial Screenshot
    os.makedirs('test_artifacts', exist_ok=True)
    subprocess.call(['scrot', 'test_artifacts/before.png'])

    # Normalized UI interactions (relative to window)
    x, y, w, h = window_info

    # Give some time for UI to settle
    time.sleep(2)

    # Move to center and click
    center_x = x + w // 2
    center_y = y + h // 2
    pyautogui.moveTo(center_x, center_y, duration=0.5)
    pyautogui.click()

    # Open settings (assuming top right menu or similar)
    # This is a safe action
    menu_x = x + w - 50
    menu_y = y + 50
    pyautogui.moveTo(menu_x, menu_y, duration=0.5)
    pyautogui.click()

    time.sleep(1)

    # Close settings (click somewhere else or click menu again)
    pyautogui.moveTo(center_x, center_y, duration=0.5)
    pyautogui.click()

    time.sleep(1)

    # Final Screenshot
    subprocess.call(['scrot', 'test_artifacts/after.png'])

    # Generate JSON result
    result = {
        "status": "success",
        "message": "Deterministic UI test completed successfully.",
        "artifacts": ["test_artifacts/before.png", "test_artifacts/after.png"],
        "window_bounds": {"x": x, "y": y, "width": w, "height": h}
    }

    with open('test_artifacts/result.json', 'w') as f:
        json.dump(result, f, indent=2)

    print("Test completed successfully.")

if __name__ == "__main__":
    main()
