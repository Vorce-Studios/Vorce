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
    parser = argparse.ArgumentParser(description="Vorce UI Test Harness")
    parser.add_argument("--env-check", action="store_true", help="Run environment check only")
    parser.add_argument("--timeout", type=int, default=60, help="Hard timeout in seconds")
    parser.add_argument("--vorce-exe", type=str, default=str(Path(__file__).parent.parent.parent.parent / "target/release/vorce.exe"), help="Path to Vorce executable")
    args = parser.parse_args()

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = ARTIFACT_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    if MISSING_DEPS:
        log_report("FAIL", f"Missing Python dependencies: {', '.join(MISSING_DEPS)}", run_dir)
        sys.exit(1)

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        log_report("FAIL", "Missing GEMINI_API_KEY in environment", run_dir)
        sys.exit(1)

    if args.env_check:
        log_report("PASS", "Environment check passed", run_dir)
        sys.exit(0)

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
    window_found = False
    start_time = time.time()
    while time.time() - start_time < args.timeout:
        try:
            windows = gw.getWindowsWithTitle("Vorce")
            if windows:
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

    # Run for a bit to verify stability, or run steps
    time.sleep(2)
    screenshot_path = take_screenshot(run_dir, "success_window")

    # Final pass tear down
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
    log_file.close()

    log_report("PASS", "Test harness ran successfully", run_dir, {"screenshot": screenshot_path})
    sys.exit(0)

if __name__ == "__main__":
    main()
