import os
import sys
import json
import time
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

# Missing dependencies tracker
MISSING_DEPS = []
try:
    import pyautogui
except ImportError:
    MISSING_DEPS.append("pyautogui")
try:
    import PIL.ImageGrab
except ImportError:
    MISSING_DEPS.append("Pillow")
try:
    import pygetwindow as gw
except ImportError:
    MISSING_DEPS.append("pygetwindow")
except NotImplementedError:
    pass # Handle gracefully on Linux

ARTIFACT_DIR = Path("artifacts/visual-capture/ui-test-runs")

def log_report(status, message, run_dir, extra_data=None):
    report = {
        "status": status,
        "message": message,
        "timestamp": datetime.now().isoformat(),
    }
    if extra_data:
        report.update(extra_data)

    report_file = run_dir / "smoke_report.json"
    with open(report_file, "w") as f:
        json.dump(report, f, indent=2)
    print(f"[{status}] {message}")
    print(f"Report saved to {report_file}")

def take_screenshot(run_dir, name="screenshot"):
    if "Pillow" in MISSING_DEPS:
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
    parser = argparse.ArgumentParser(description="Deterministic Vorce UI Smoke Test")
    parser.add_argument("--timeout", type=int, default=60, help="Hard timeout in seconds")
    parser.add_argument("--vorce-exe", type=str, default=str(Path(__file__).parent.parent.parent.parent / "target/release/vorce.exe"), help="Path to Vorce executable")
    args = parser.parse_args()

    run_id = datetime.now().strftime("smoke_%Y%m%d_%H%M%S")
    run_dir = ARTIFACT_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    if MISSING_DEPS:
        log_report("FAIL", f"Missing Python dependencies: {', '.join(MISSING_DEPS)}", run_dir)
        sys.exit(1)

    print(f"Starting Vorce from {args.vorce_exe}...")
    if not os.path.exists(args.vorce_exe):
        screenshot_path = take_screenshot(run_dir, "failure_launch")
        log_report("FAIL", f"Vorce launch failure: executable not found at {args.vorce_exe}", run_dir, {"screenshot": screenshot_path})
        sys.exit(1)

    log_file_path = run_dir / "vorce_output.log"
    log_file = open(log_file_path, "w")
    try:
        process = subprocess.Popen([args.vorce_exe], stdout=log_file, stderr=subprocess.STDOUT)
    except Exception as e:
        screenshot_path = take_screenshot(run_dir, "failure_launch")
        log_report("FAIL", f"Vorce launch failure: {e}", run_dir, {"screenshot": screenshot_path})
        sys.exit(1)

    # Wait for window
    vorce_window = None
    start_time = time.time()

    # Try to get window using pygetwindow
    if "pygetwindow" not in MISSING_DEPS:
        try:
            import pygetwindow as gw
            while time.time() - start_time < args.timeout:
                try:
                    windows = gw.getWindowsWithTitle("Vorce")
                    if windows:
                        vorce_window = windows[0]
                        break
                except Exception:
                    pass
                time.sleep(1)
        except NotImplementedError:
            print("pygetwindow not supported on this OS, skipping window bounds check.")

    if not vorce_window and "pygetwindow" not in MISSING_DEPS and sys.platform == "win32":
        screenshot_path = take_screenshot(run_dir, "failure_no_window")
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        log_file.close()
        log_report("FAIL", "No window found within timeout", run_dir, {"screenshot": screenshot_path})
        sys.exit(1)

    time.sleep(2)
    take_screenshot(run_dir, "before_actions")

    print("Executing fixed mouse flow...")
    try:
        if vorce_window:
            # Use normalized window coordinates if available
            base_x = vorce_window.left
            base_y = vorce_window.top
            width = vorce_window.width
            height = vorce_window.height

            # Action 1: Move and click near the top-left (e.g. menu)
            pyautogui.moveTo(base_x + int(width * 0.1), base_y + int(height * 0.1), duration=0.5)
            pyautogui.click()
            time.sleep(0.5)

            # Action 2: Move and click in a stable panel area
            pyautogui.moveTo(base_x + int(width * 0.8), base_y + int(height * 0.2), duration=0.5)
            pyautogui.click()
            time.sleep(0.5)

            # Action 3: Click in the center area
            pyautogui.moveTo(base_x + int(width * 0.5), base_y + int(height * 0.5), duration=0.5)
            pyautogui.click()
            time.sleep(0.5)

            # Action 4: Reset state, move back
            pyautogui.moveTo(base_x + int(width * 0.1), base_y + int(height * 0.1), duration=0.5)
            pyautogui.click()
        else:
            # Fallback for Linux or if window bounds not found: execute fixed absolute coords
            pyautogui.moveTo(100, 100, duration=0.5)
            pyautogui.click()
            time.sleep(0.5)

            pyautogui.moveTo(800, 200, duration=0.5)
            pyautogui.click()
            time.sleep(0.5)

            pyautogui.moveTo(500, 500, duration=0.5)
            pyautogui.click()
            time.sleep(0.5)

            pyautogui.moveTo(100, 100, duration=0.5)
            pyautogui.click()
    except Exception as e:
        screenshot_path = take_screenshot(run_dir, "failure_during_actions")
        process.terminate()
        log_file.close()
        log_report("FAIL", f"Action execution failed: {e}", run_dir, {"screenshot": screenshot_path})
        sys.exit(1)

    time.sleep(1)
    screenshot_path = take_screenshot(run_dir, "after_actions")

    # Final pass tear down
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
    log_file.close()

    log_report("PASS", "Smoke test actions executed successfully", run_dir, {"screenshot": screenshot_path})
    sys.exit(0)

if __name__ == "__main__":
    main()
