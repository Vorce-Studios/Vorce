import os
import sys
import json
import time
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

try:
    import pyautogui
except ImportError:
    print("Error: pyautogui is required for this smoke test.")
    sys.exit(1)

try:
    import PIL.ImageGrab
    HAS_PILLOW = True
except ImportError:
    print("Error: Pillow is required for this smoke test.")
    sys.exit(1)

try:
    import pygetwindow as gw
except ImportError:
    print("Error: pygetwindow is required for this smoke test.")
    sys.exit(1)

ARTIFACT_DIR = Path("artifacts/visual-capture/ui-test-runs")

def log_report(status, message, run_dir, extra_data=None):
    report = {
        "status": status,
        "message": message,
        "timestamp": datetime.now().isoformat(),
    }
    if extra_data:
        report.update(extra_data)

    report_file = run_dir / "run_report.json"
    with open(report_file, "w") as f:
        json.dump(report, f, indent=2)
    print(f"[{status}] {message}")
    print(f"Report saved to {report_file}")

def take_screenshot(run_dir, name="screenshot"):
    if not HAS_PILLOW:
        return None
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = run_dir / f"{name}_{timestamp}.png"
        img = PIL.ImageGrab.grab()
        img.save(filename)
        return str(filename)
    except Exception as e:
        print(f"Failed to take screenshot: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Vorce UI Smoke Test")
    parser.add_argument("--timeout", type=int, default=60, help="Hard timeout in seconds")
    parser.add_argument("--vorce-exe", type=str, default=str(Path(__file__).parent.parent.parent.parent / "target/release/vorce.exe"), help="Path to Vorce executable")
    args = parser.parse_args()

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = ARTIFACT_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    print(f"Starting Vorce from {args.vorce_exe}...")
    if not os.path.exists(args.vorce_exe):
        log_report("FAIL", f"Vorce executable not found at {args.vorce_exe}", run_dir)
        sys.exit(1)

    log_file_path = run_dir / "vorce_output.log"
    log_file = open(log_file_path, "w")
    try:
        process = subprocess.Popen([args.vorce_exe], stdout=log_file, stderr=subprocess.STDOUT)
    except Exception as e:
        screenshot_path = take_screenshot(run_dir, "failure_launch")
        log_report("FAIL", f"Vorce launch failure: {e}", run_dir, {"screenshot": screenshot_path})
        log_file.close()
        sys.exit(1)

    # Wait for window
    window_found = False
    start_time = time.time()
    main_window = None

    print("Waiting for Vorce window...")
    while time.time() - start_time < args.timeout:
        try:
            windows = gw.getWindowsWithTitle("Vorce")
            if windows:
                main_window = windows[0]
                window_found = True
                break
        except Exception:
            pass
        time.sleep(1)

    if not window_found:
        screenshot_path = take_screenshot(run_dir, "failure_no_window")
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        log_file.close()
        log_report("FAIL", "No window found within timeout", run_dir, {"screenshot": screenshot_path})
        sys.exit(1)

    print(f"Window bounds: ({main_window.left}, {main_window.top}) -> ({main_window.width}x{main_window.height})")
    screenshot_before = take_screenshot(run_dir, "before_actions")

    # Execute deterministic actions
    print("Executing deterministic UI actions...")
    try:
        # Activate window
        try:
            main_window.activate()
        except:
            pass

        time.sleep(0.5)

        # Base coordinates from window position
        base_x = main_window.left
        base_y = main_window.top
        w = main_window.width
        h = main_window.height

        # Action 1: Open Settings (assuming top-left menu or header button)
        # Normalized coordinates: 5% x, 5% y
        settings_x = base_x + int(w * 0.05)
        settings_y = base_y + int(h * 0.05)
        print(f"Clicking Settings at ({settings_x}, {settings_y})")
        pyautogui.moveTo(settings_x, settings_y, duration=0.2)
        pyautogui.click()
        time.sleep(1)

        # Action 2: Select a stable panel (e.g., center screen)
        panel_x = base_x + int(w * 0.5)
        panel_y = base_y + int(h * 0.5)
        print(f"Clicking Panel at ({panel_x}, {panel_y})")
        pyautogui.moveTo(panel_x, panel_y, duration=0.2)
        pyautogui.click()
        time.sleep(1)

        # Action 3: Close or reset transient state (e.g., click an empty area or close button)
        # Assuming top-right close dialog or similar safe area
        close_x = base_x + int(w * 0.9)
        close_y = base_y + int(h * 0.1)
        print(f"Clicking Close/Reset at ({close_x}, {close_y})")
        pyautogui.moveTo(close_x, close_y, duration=0.2)
        pyautogui.click()
        time.sleep(1)

    except Exception as e:
        screenshot_path = take_screenshot(run_dir, "failure_actions")
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        log_file.close()
        log_report("FAIL", f"Failed during UI actions: {e}", run_dir, {"screenshot": screenshot_path})
        sys.exit(1)

    screenshot_after = take_screenshot(run_dir, "after_actions")

    # Final tear down
    print("Tearing down...")
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()

    log_file.close()

    log_report("PASS", "Smoke test ran successfully", run_dir, {
        "screenshot_before": screenshot_before,
        "screenshot_after": screenshot_after
    })
    sys.exit(0)

if __name__ == "__main__":
    main()
