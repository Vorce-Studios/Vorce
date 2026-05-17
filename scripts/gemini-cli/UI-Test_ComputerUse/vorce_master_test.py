import argparse
import sys
import os
import json
import time
import subprocess
import threading
from datetime import datetime

# Ensure output directory exists and is ignored
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)
with open(os.path.join(OUTPUT_DIR, ".gitignore"), "w") as f:
    f.write("*\n")

def check_environment():
    """Checks for required environment variables and dependencies."""
    missing = []

    # Check OS
    if os.name != 'nt':
        missing.append("Windows OS (required for this harness)")

    # Check API key
    if not os.environ.get("GEMINI_API_KEY"):
        missing.append("GEMINI_API_KEY environment variable")

    # Check imports
    try:
        import pyautogui
    except ImportError:
        missing.append("pyautogui python package")

    try:
        import PIL
    except ImportError:
        missing.append("pillow python package")

    try:
        import google.genai
    except ImportError:
        missing.append("google-genai python package")

    try:
        import psutil
    except ImportError:
        missing.append("psutil python package")

    # Handle pygetwindow Windows-only restriction gracefully
    if os.name == 'nt':
        try:
            import pygetwindow
        except ImportError:
            missing.append("pygetwindow python package")

    return missing

def save_artifact(filename, content, is_binary=False):
    """Saves an artifact to the output directory."""
    filepath = os.path.join(OUTPUT_DIR, filename)
    mode = 'wb' if is_binary else 'w'
    with open(filepath, mode) as f:
        f.write(content)
    return filepath

def run_test_logic(task, report, proc_container):
    """Internal test logic executed within a thread for timeout handling."""
    # Deferred imports to ensure check_environment can run without ModuleNotFoundErrors
    from wait_for_vorce import build_vorce, start_vorce, wait_for_window
    from vorce_pilot import run_vision_loop, get_screenshot

    # 2. Build
    print("\n[2] Building Vorce...")
    if not build_vorce():
        report["status"] = "failed"
        report["errors"].append("Build failed.")
        save_artifact("run_report.json", json.dumps(report, indent=2))
        return False

    # 3. Launch
    print("\n[3] Launching Vorce...")
    stdout_path = os.path.join(OUTPUT_DIR, "launch_log_stdout.txt")
    stderr_path = os.path.join(OUTPUT_DIR, "launch_log_stderr.txt")

    proc = start_vorce(log_stdout_path=stdout_path, log_stderr_path=stderr_path)
    proc_container["proc"] = proc
    if not proc:
        report["status"] = "failed"
        report["errors"].append("Failed to start Vorce process.")
        save_artifact("run_report.json", json.dumps(report, indent=2))
        return False

    # 4. Wait for Window
    print("\n[4] Waiting for Vorce window...")
    if not wait_for_window():
        report["status"] = "failed"
        report["errors"].append("Timeout waiting for Vorce window.")

        # Capture failure screenshot
        screenshot = get_screenshot()
        if screenshot:
            screenshot_path = os.path.join(OUTPUT_DIR, "failure_screenshot.png")
            screenshot.save(screenshot_path)
            report["screenshot"] = "failure_screenshot.png"
        else:
            report["errors"].append("Failed to capture screenshot.")

        return False

    print("Window detected.")

    # 5. Execute Task (mocked for now)
    print(f"\n[5] Executing task: {task}")
    success = run_vision_loop(task)

    if success:
        print(f"Task '{task}' completed successfully.")
        report["status"] = "passed"
    else:
        print(f"Task '{task}' failed.")
        report["status"] = "failed"
        report["errors"].append("Vision loop reported failure.")

        # Capture failure screenshot
        screenshot = get_screenshot()
        if screenshot:
            screenshot_path = os.path.join(OUTPUT_DIR, "failure_screenshot.png")
            screenshot.save(screenshot_path)
            report["screenshot"] = "failure_screenshot.png"

    return success

def run_test(task="noop", timeout=120):
    """Runs the full test lifecycle with a hard timeout."""
    report = {
        "timestamp": datetime.now().isoformat(),
        "task": task,
        "status": "started",
        "errors": []
    }

    print(f"--- Starting Vorce UI Automation Harness ---")
    print(f"Task: {task}")
    print(f"Timeout: {timeout} seconds")

    # 1. Environment Check
    print("\n[1] Checking environment...")
    missing_reqs = check_environment()
    if missing_reqs:
        print("Missing prerequisites:")
        for req in missing_reqs:
            print(f"  - {req}")

        # If it's just a noop check, we don't strictly need the API key to pass
        if task == "noop" and "GEMINI_API_KEY environment variable" in missing_reqs:
            print("Ignoring missing API key for noop environment check.")
            # Remove from missing reqs for strict check
            missing_reqs = [r for r in missing_reqs if r != "GEMINI_API_KEY environment variable"]

        if missing_reqs:
            report["status"] = "failed"
            report["errors"].append(f"Missing prerequisites: {', '.join(missing_reqs)}")
            save_artifact("run_report.json", json.dumps(report, indent=2))
            return False

    print("Environment OK.")

    if task == "noop":
        print("\nNo-op environment check completed successfully.")
        report["status"] = "passed"
        save_artifact("run_report.json", json.dumps(report, indent=2))
        return True

    # Use a container to extract the process object from the worker thread
    proc_container = {"proc": None}
    worker_result = [False]

    def worker():
        try:
            worker_result[0] = run_test_logic(task, report, proc_container)
        except Exception as e:
            report["status"] = "failed"
            report["errors"].append(f"Unhandled exception in test logic: {e}")
            print(f"Test crashed: {e}")

    thread = threading.Thread(target=worker)
    thread.daemon = True
    start_time = time.time()
    thread.start()

    # Wait for the thread to finish or timeout
    thread.join(timeout)

    if thread.is_alive():
        print(f"\n[!] Hard timeout reached ({timeout} seconds). Aborting test.")
        report["status"] = "failed"
        report["errors"].append(f"Test exceeded hard timeout of {timeout} seconds.")

    proc = proc_container.get("proc")

    # 6. Cleanup
    print("\n[6] Cleaning up...")
    if proc:
        print("Terminating Vorce process tree...")
        from wait_for_vorce import kill_process_tree
        try:
            kill_process_tree(proc.pid)
        except Exception as e:
            print(f"Error killing process tree: {e}")

        # Close file handles if they exist
        if hasattr(proc, '_stdout_file') and proc._stdout_file:
            try: proc._stdout_file.close()
            except: pass
        if hasattr(proc, '_stderr_file') and proc._stderr_file:
            try: proc._stderr_file.close()
            except: pass

    # Finalize report
    save_artifact("run_report.json", json.dumps(report, indent=2))
    print("Run artifacts saved to output/")

    return worker_result[0] and not thread.is_alive()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Vorce UI Automation Harness")
    parser.add_argument("--task", default="noop", help="The UI task to execute (or 'noop' for environment check)")
    parser.add_argument("--timeout", type=int, default=120, help="Hard timeout in seconds")

    args = parser.parse_args()

    success = run_test(task=args.task, timeout=args.timeout)
    sys.exit(0 if success else 1)
