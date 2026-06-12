import argparse
import ctypes
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
ARTIFACT_ROOT = REPO_ROOT / "artifacts" / "visual-capture" / "ui-test-runs"
DEFAULT_WINDOW_TITLE = "Vorce"


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def default_exe_path():
    release_exe = REPO_ROOT / "target" / "release" / "vorce.exe"
    debug_exe = REPO_ROOT / "target" / "debug" / "vorce.exe"
    if release_exe.exists():
        return release_exe
    return debug_exe


def make_run_dir(mode):
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = ARTIFACT_ROOT / f"{mode}-{run_id}"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


class RunReport:
    def __init__(self, mode, run_dir, args):
        self.mode = mode
        self.run_dir = run_dir
        self.data = {
            "mode": mode,
            "status": "running",
            "started_at": now_iso(),
            "ended_at": None,
            "repo_root": str(REPO_ROOT),
            "run_dir": str(run_dir),
            "arguments": vars(args),
            "checks": [],
            "artifacts": {},
        }

    def check(self, name, status, message, **extra):
        entry = {
            "name": name,
            "status": status,
            "message": message,
            "timestamp": now_iso(),
        }
        entry.update(extra)
        self.data["checks"].append(entry)
        print(f"[{status.upper()}] {name}: {message}")
        return status != "fail"

    def artifact(self, name, path):
        if path:
            self.data["artifacts"][name] = str(path)

    def finish(self, status, message, failure_reason=None):
        self.data["status"] = status
        self.data["message"] = message
        self.data["ended_at"] = now_iso()

        if status == "failed":
            self.data["failure_reason"] = failure_reason or "unknown_error"
            self.data["scenario_name"] = self.mode
            self.data["log_path"] = self.data["artifacts"].get("process_log")
            self.data["screenshot"] = self.data["artifacts"].get("initial_screenshot")

        report_path = self.run_dir / "run_report.json"
        report_path.write_text(json.dumps(self.data, indent=2), encoding="utf-8")
        print(f"[{status.upper()}] {message}")
        print(f"Report: {report_path}")
        return 0 if status == "passed" else 1


def import_optional(module_name):
    try:
        __import__(module_name)
        return True, None
    except Exception as exc:
        return False, str(exc)


def capture_screenshot(path):
    try:
        from PIL import ImageGrab

        image = ImageGrab.grab()
        image.save(path)
        return True, None
    except Exception as exc:
        return False, str(exc)


def list_windows():
    if os.name != "nt":
        return []

    windows = []

    EnumWindows = ctypes.windll.user32.EnumWindows
    IsWindowVisible = ctypes.windll.user32.IsWindowVisible
    GetWindowTextLengthW = ctypes.windll.user32.GetWindowTextLengthW
    GetWindowTextW = ctypes.windll.user32.GetWindowTextW
    GetWindowThreadProcessId = ctypes.windll.user32.GetWindowThreadProcessId

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def callback(hwnd, _):
        if not IsWindowVisible(hwnd):
            return True
        length = GetWindowTextLengthW(hwnd)
        if length <= 0:
            return True
        buffer = ctypes.create_unicode_buffer(length + 1)
        GetWindowTextW(hwnd, buffer, length + 1)
        title = buffer.value.strip()
        if title:
            process_id = ctypes.c_ulong()
            GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
            windows.append({"hwnd": int(hwnd), "pid": process_id.value, "title": title})
        return True

    EnumWindows(callback, None)
    return windows


def wait_for_window(title_contains, timeout_seconds, process=None, match_process=True):
    deadline = time.monotonic() + timeout_seconds
    last_windows = []
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            return False, last_windows, f"process exited with code {process.returncode}"
        last_windows = list_windows()
        for window in last_windows:
            title_matches = title_contains.lower() in window["title"].lower()
            process_matches = process is None or window["pid"] == process.pid or not match_process
            if title_matches and process_matches:
                return True, last_windows, window["title"]
        time.sleep(0.5)
    if process is not None and match_process:
        return False, last_windows, f"no visible window for pid {process.pid} containing '{title_contains}'"
    return False, last_windows, f"no visible window containing '{title_contains}'"


def check_environment(report, args):
    ok = True
    ok &= report.check("python", "pass", sys.version.split()[0], executable=sys.executable)
    ok &= report.check("repo_root", "pass" if REPO_ROOT.exists() else "fail", str(REPO_ROOT))

    exe_path = Path(args.vorce_exe)
    exe_required = args.mode == "launch-check"
    exe_status = "pass" if exe_path.exists() else ("fail" if exe_required else "warn")
    ok &= report.check(
        "vorce_exe",
        exe_status,
        str(exe_path) if exe_path.exists() else f"not built yet: {exe_path}",
    )

    pillow_ok, pillow_error = import_optional("PIL.ImageGrab")
    report.check(
        "pillow",
        "pass" if pillow_ok else "warn",
        "Pillow screenshot support available" if pillow_ok else f"Pillow unavailable: {pillow_error}",
    )

    mouse_ok, mouse_error = import_optional("pyautogui")
    report.check(
        "pyautogui",
        "pass" if mouse_ok else "warn",
        "pyautogui mouse/keyboard support available" if mouse_ok else f"pyautogui unavailable: {mouse_error}",
    )

    if args.require_gemini_key:
        key_present = bool(os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
        ok &= report.check(
            "gemini_api_key",
            "pass" if key_present else "fail",
            "Gemini API key present" if key_present else "Set GEMINI_API_KEY or GOOGLE_API_KEY",
        )
    else:
        key_present = bool(os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
        report.check(
            "gemini_api_key",
            "pass" if key_present else "warn",
            "Gemini API key present" if key_present else "not required for this mode",
        )

    if args.require_screenshot:
        ok &= report.check(
            "screenshot_prereq",
            "pass" if pillow_ok else "fail",
            "Pillow is required because --require-screenshot is set",
        )

    return ok


def run_env_check(report, args):
    ok = check_environment(report, args)
    return report.finish("passed" if ok else "failed", "environment check completed", failure_reason="env_check_failed" if not ok else None)


def run_launch_check(report, args):
    ok = check_environment(report, args)
    if not ok:
        return report.finish("failed", "launch check blocked by missing prerequisites", failure_reason="missing_prerequisites")

    exe_path = Path(args.vorce_exe)
    log_path = report.run_dir / "vorce_process.log"
    report.artifact("process_log", log_path)

    log_file = log_path.open("w", encoding="utf-8", errors="replace")
    process = None
    try:
        report.check("launch", "pass", f"starting {exe_path}")
        process = subprocess.Popen(
            [str(exe_path)],
            cwd=str(REPO_ROOT),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
        )

        found, windows, detail = wait_for_window(
            args.window_title,
            args.timeout,
            process,
            match_process=not args.allow_any_process_window,
        )
        windows_path = report.run_dir / "window_titles.json"
        windows_path.write_text(json.dumps(windows, indent=2), encoding="utf-8")
        report.artifact("window_titles", windows_path)
        report.check(
            "window",
            "pass" if found else "fail",
            detail,
            sampled_windows=windows[:20],
        )

        screenshot_ok = True
        if args.capture_screenshot:
            screenshot_path = report.run_dir / "initial_window.png"
            screenshot_ok, error = capture_screenshot(screenshot_path)
            if screenshot_ok:
                report.artifact("initial_screenshot", screenshot_path)
            report.check(
                "screenshot",
                "pass" if screenshot_ok else ("fail" if args.require_screenshot else "warn"),
                "captured initial screenshot" if screenshot_ok else f"screenshot failed: {error}",
            )

        if found and screenshot_ok:
            return report.finish("passed", "launch check completed")
        failure_reason = "window_not_found" if not found else "screenshot_failed"
        return report.finish("failed", "launch check failed", failure_reason=failure_reason)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        log_file.close()


def parse_args():
    parser = argparse.ArgumentParser(description="Vorce UI automation harness")
    parser.add_argument(
        "--mode",
        choices=["env-check", "launch-check"],
        default="env-check",
        help="env-check validates prerequisites without launching Vorce; launch-check starts Vorce and waits for a window.",
    )
    parser.add_argument("--timeout", type=int, default=45, help="Hard timeout in seconds for launch/window checks.")
    parser.add_argument("--window-title", default=DEFAULT_WINDOW_TITLE, help="Visible window title substring to wait for.")
    parser.add_argument("--vorce-exe", default=str(default_exe_path()), help="Path to vorce.exe.")
    parser.add_argument(
        "--allow-any-process-window",
        action="store_true",
        help="Match any visible window title instead of requiring the launched process PID.",
    )
    parser.add_argument("--require-gemini-key", action="store_true", help="Fail if GEMINI_API_KEY/GOOGLE_API_KEY is missing.")
    parser.add_argument("--require-screenshot", action="store_true", help="Fail if screenshot capture is unavailable.")
    parser.add_argument("--no-screenshot", dest="capture_screenshot", action="store_false", help="Skip screenshot capture.")
    parser.set_defaults(capture_screenshot=True)
    return parser.parse_args()


def main():
    args = parse_args()
    run_dir = make_run_dir(args.mode)
    report = RunReport(args.mode, run_dir, args)

    if args.mode == "env-check":
        return run_env_check(report, args)
    if args.mode == "launch-check":
        return run_launch_check(report, args)
    return report.finish("failed", f"unsupported mode: {args.mode}")


if __name__ == "__main__":
    raise SystemExit(main())
