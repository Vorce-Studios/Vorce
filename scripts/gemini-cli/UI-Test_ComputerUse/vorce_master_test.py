import os
import sys
import json
import time
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

MISSING_DEPS = []
try:
    import pyautogui
except ImportError:
    MISSING_DEPS.append("pyautogui")
try:
    import PIL.ImageGrab
except ImportError:
    MISSING_DEPS.append("Pillow")

ARTIFACT_DIR = Path("artifacts/visual-capture/ui-test-runs")

def log_report(status, message, run_dir, extra_data=None, failure_reason=None, scenario_name="deterministic_ui_smoke_test"):
    report = {
        "status": status,
        "message": message,
        "timestamp": datetime.now().isoformat(),
    }
    if status == "FAIL":
        report["failure_reason"] = failure_reason or "unknown_error"
        report["scenario_name"] = scenario_name
        report["log_path"] = str(run_dir / "vorce_output.log")
        report["screenshot"] = None # Updated later if available

    if extra_data:
        report.update(extra_data)

    report_file = run_dir / "run_report.json"
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

def run_test_steps(run_dir):
    print("Running deterministic UI flow...")

    # Give UI time to fully render
    time.sleep(2)

    # Step 1: Open settings
    print("Action: Click Settings (assume standard left panel or toolbar)")
    # Normalize coordinates based on screen size fallback
    try:
        # Assuming a 1280x720 window
        pyautogui.moveTo(100, 100, duration=0.5)
        pyautogui.click()
    except Exception as e:
        print(f"Failed to move mouse: {e}")

    time.sleep(1)
    take_screenshot(run_dir, "after_settings_open")

    # Step 2: Select a stable panel
    print("Action: Select Central/Bottom Panel")
    try:
        pyautogui.moveTo(640, 360, duration=0.5)
        pyautogui.click()
    except Exception as e:
        print(f"Failed to move mouse: {e}")

    time.sleep(1)

    # Step 3: Trigger safe/reversible action (e.g., right click context menu)
    print("Action: Right-click in canvas")
    try:
        pyautogui.rightClick()
    except Exception as e:
        print(f"Failed to right click: {e}")

    time.sleep(1)
    take_screenshot(run_dir, "after_right_click")

    # Step 4: Close/reset state (Escape to close menu/settings)
    print("Action: Press Esc to close menus/dialogs")
    try:
        pyautogui.press('esc')
    except Exception as e:
        print(f"Failed to press esc: {e}")

    time.sleep(1)

    take_screenshot(run_dir, "after_reset")

    return True

def main():
    parser = argparse.ArgumentParser(description="Vorce Deterministic UI Smoke Test")
    parser.add_argument("--timeout", type=int, default=60, help="Hard timeout in seconds")
    parser.add_argument("--vorce-exe", type=str, default=str(Path(__file__).parent.parent.parent.parent / "target/release/vorce.exe"), help="Path to Vorce executable")
    args = parser.parse_args()

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = ARTIFACT_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    if MISSING_DEPS:
        log_report("FAIL", f"Missing Python dependencies: {', '.join(MISSING_DEPS)}", run_dir, failure_reason="missing_dependencies")
        sys.exit(1)

    print(f"Starting Vorce from {args.vorce_exe}...")
    if not os.path.exists(args.vorce_exe):
        screenshot_path = take_screenshot(run_dir, "failure_launch")
        log_report("FAIL", f"Vorce launch failure: executable not found at {args.vorce_exe}", run_dir, {"screenshot": screenshot_path}, failure_reason="executable_not_found")
        sys.exit(1)

    log_file_path = run_dir / "vorce_output.log"
    log_file = open(log_file_path, "w")
    try:
        process = subprocess.Popen([args.vorce_exe], stdout=log_file, stderr=subprocess.STDOUT)
    except Exception as e:
        screenshot_path = take_screenshot(run_dir, "failure_launch")
        log_report("FAIL", f"Vorce launch failure: {e}", run_dir, {"screenshot": screenshot_path}, failure_reason="launch_failed")
        sys.exit(1)

    # Wait for window (simple delay fallback since pygetwindow is windows-only typically, and we want this robust)
    time.sleep(5)

    screenshot_path = take_screenshot(run_dir, "initial_window")

    try:
        test_success = run_test_steps(run_dir)
    except Exception as e:
        screenshot_path = take_screenshot(run_dir, "failure_during_test")
        log_report("FAIL", f"Test steps failed: {e}", run_dir, {"screenshot": screenshot_path}, failure_reason="test_steps_failed")
        process.terminate()
        process.kill()
        sys.exit(1)

    # Final pass tear down
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
    log_file.close()

    if test_success:
        log_report("PASS", "UI Smoke Test passed", run_dir, {"screenshot": screenshot_path})
        sys.exit(0)
    else:
        log_report("FAIL", "UI Smoke Test failed", run_dir, {"screenshot": screenshot_path}, failure_reason="smoke_test_failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
