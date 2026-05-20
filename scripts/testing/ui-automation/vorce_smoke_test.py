#!/usr/bin/env python3
import sys
import os
import time
import json
import subprocess
import argparse
from pathlib import Path

try:
    import pyautogui
    import pygetwindow as gw
    from PIL import Image, ImageChops
    import psutil
except ImportError as e:
    print(f"Error: Missing dependency - {e}")
    print("Please install requirements: pip install pyautogui pillow psutil pygetwindow")
    sys.exit(1)

# Fail safe: Moving mouse to any corner of the screen will abort pyautogui
pyautogui.FAILSAFE = True

# Constants
TEST_OUTPUT_DIR = Path("smoke_test_artifacts")
STARTUP_TIMEOUT_SECONDS = 30
INTERACTION_DELAY = 1.0

def find_vorce_process():
    """Find the running vorce process."""
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            if 'vorce' in proc.info['name'].lower() and 'test' not in proc.info['name'].lower():
                return proc
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
    return None

def wait_for_vorce(timeout=STARTUP_TIMEOUT_SECONDS):
    """Wait for vorce to start and become visible."""
    print(f"Waiting up to {timeout} seconds for Vorce to start...")
    start_time = time.time()

    while time.time() - start_time < timeout:
        proc = find_vorce_process()
        if proc:
            print(f"Found Vorce process (PID: {proc.pid})")
            # Give it a bit more time to initialize the window
            time.sleep(3)
            return True
        time.sleep(1)

    print("Timeout waiting for Vorce process.")
    return False

def take_screenshot(name):
    """Take a screenshot and save it to the artifacts directory."""
    if not TEST_OUTPUT_DIR.exists():
        TEST_OUTPUT_DIR.mkdir(parents=True)

    filepath = TEST_OUTPUT_DIR / f"{name}.png"
    screenshot = pyautogui.screenshot()
    screenshot.save(filepath)
    print(f"Saved screenshot: {filepath}")
    return filepath

def get_vorce_window():
    """Find the Vorce window to get bounds."""
    windows = gw.getWindowsWithTitle('Vorce')
    if windows:
        return windows[0]
    return None

def execute_mouse_flow():
    """Execute a fixed sequence of mouse movements and clicks."""
    print("Executing UI interaction flow...")

    window = get_vorce_window()
    if window:
        print(f"Found Vorce window: {window.title} at ({window.left}, {window.top}) size {window.width}x{window.height}")
        # Bring window to front
        try:
            window.activate()
            time.sleep(0.5)
        except Exception as e:
            print(f"Could not activate window: {e}")

        base_x = window.left
        base_y = window.top
        width = window.width
        height = window.height
    else:
        print("Warning: Could not find Vorce window. Falling back to full screen coordinates.")
        screen_width, screen_height = pyautogui.size()
        base_x = 0
        base_y = 0
        width = screen_width
        height = screen_height

    # 2. Click roughly where the settings menu might be (top left cornerish)
    # Using window-relative normalized coordinates
    settings_x = base_x + int(width * 0.05)
    settings_y = base_y + int(height * 0.05)

    print(f"Moving to 'Settings/Menu' area ({settings_x}, {settings_y})")
    pyautogui.moveTo(settings_x, settings_y, duration=0.5)
    pyautogui.click()
    time.sleep(INTERACTION_DELAY)
    take_screenshot("02_after_menu_click")

    # 3. Click somewhere safe in the middle/bottom to select a stable panel
    panel_x = base_x + int(width * 0.5)
    panel_y = base_y + int(height * 0.8)

    print(f"Moving to 'Panel' area ({panel_x}, {panel_y})")
    pyautogui.moveTo(panel_x, panel_y, duration=0.5)
    pyautogui.click()
    time.sleep(INTERACTION_DELAY)
    take_screenshot("03_after_panel_click")

    # 4. Press Escape to reset any transient dialogs/states
    print("Pressing 'Escape' to clear state")
    pyautogui.press('esc')
    time.sleep(INTERACTION_DELAY)
    take_screenshot("04_after_escape")

def main():
    parser = argparse.ArgumentParser(description="Deterministic Vorce UI Smoke Test")
    parser.add_argument("--launch-cmd", type=str, default="cargo run --release",
                        help="Command to launch Vorce")
    parser.add_argument("--skip-launch", action="store_true",
                        help="Skip launching Vorce and attach to an existing instance")
    args = parser.parse_args()

    results = {
        "status": "failed",
        "steps_completed": [],
        "error": None
    }

    # Ensure artifacts directory exists and is clean
    if TEST_OUTPUT_DIR.exists():
        for file in TEST_OUTPUT_DIR.glob("*.png"):
            file.unlink()
    else:
        TEST_OUTPUT_DIR.mkdir(parents=True)

    vorce_process = None

    try:
        if not args.skip_launch:
            print(f"Launching Vorce: {args.launch_cmd}")
            # Run in background
            vorce_process = subprocess.Popen(args.launch_cmd, shell=True,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            results["steps_completed"].append("launch")

        # 1. Wait for Vorce to start
        if not wait_for_vorce():
            raise Exception("Vorce did not start within the timeout period.")
        results["steps_completed"].append("wait_for_startup")

        # 2. Capture initial state
        take_screenshot("01_initial_state")
        results["steps_completed"].append("initial_screenshot")

        # 3 & 4. Execute flow and capture screenshots
        execute_mouse_flow()
        results["steps_completed"].append("mouse_flow")

        # Test passed!
        results["status"] = "passed"
        print("\n✅ Smoke test completed successfully!")

    except Exception as e:
        results["error"] = str(e)
        print(f"\n❌ Smoke test failed: {e}")
        take_screenshot("99_failure_state")

    finally:
        # Write results JSON
        results_file = TEST_OUTPUT_DIR / "results.json"
        with open(results_file, "w") as f:
            json.dump(results, f, indent=2)
        print(f"Wrote results to {results_file}")

        # Clean up process if we launched it
        if vorce_process and vorce_process.poll() is None:
            print("Terminating Vorce process...")
            vorce_process.terminate()
            try:
                vorce_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                vorce_process.kill()

    sys.exit(0 if results["status"] == "passed" else 1)

if __name__ == "__main__":
    main()
