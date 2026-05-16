import subprocess
import time
import os
import sys
import psutil

def build_vorce():
    """Builds the Vorce app."""
    print("Building Vorce...")
    # Assuming we run from repo root or adapt path
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
    try:
        result = subprocess.run(
            ["cargo", "build", "--release", "-p", "vorce", "--bin", "Vorce", "--no-default-features", "--features", "audio,ffmpeg"],
            cwd=repo_root,
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print("Build failed.")
            print(result.stderr)
            return False
        print("Build succeeded.")
        return True
    except FileNotFoundError:
        print("Cargo not found. Is Rust installed?")
        return False

def start_vorce(log_stdout_path=None, log_stderr_path=None):
    """Starts the Vorce app and returns the process object.
    Stdout and stderr are redirected to files to prevent buffer deadlock."""
    print("Starting Vorce...")
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))

    env = os.environ.copy()

    stdout_dest = open(log_stdout_path, 'w') if log_stdout_path else subprocess.DEVNULL
    stderr_dest = open(log_stderr_path, 'w') if log_stderr_path else subprocess.DEVNULL

    try:
        run_bat = os.path.join(repo_root, "scripts", "vorce", "run-vorce.bat")
        if os.path.exists(run_bat):
            process = subprocess.Popen(
                [run_bat],
                cwd=repo_root,
                stdout=stdout_dest,
                stderr=stderr_dest,
                text=True,
                env=env
            )
        else:
            process = subprocess.Popen(
                ["cargo", "run", "--release", "-p", "vorce", "--bin", "Vorce", "--no-default-features", "--features", "audio,ffmpeg"],
                cwd=repo_root,
                stdout=stdout_dest,
                stderr=stderr_dest,
                text=True,
                env=env
            )
        # Store file handles on the process object so we can close them later
        process._stdout_file = stdout_dest if log_stdout_path else None
        process._stderr_file = stderr_dest if log_stderr_path else None
        return process
    except Exception as e:
        print(f"Failed to start Vorce: {e}")
        if log_stdout_path and stdout_dest != subprocess.DEVNULL: stdout_dest.close()
        if log_stderr_path and stderr_dest != subprocess.DEVNULL: stderr_dest.close()
        return None

def wait_for_window(timeout=30):
    """Waits for the Vorce window to appear by checking window titles."""
    print(f"Waiting up to {timeout} seconds for Vorce window...")
    start_time = time.time()

    try:
        import pygetwindow as gw

        while time.time() - start_time < timeout:
            titles = gw.getAllTitles()
            # Vorce window is usually just named "Vorce"
            if any("Vorce" in title for title in titles if title.strip()):
                print("Vorce window detected via pygetwindow.")
                time.sleep(1) # Give it a brief moment to finish rendering
                return True
            time.sleep(1)

    except ImportError:
        print("pygetwindow not installed. Falling back to process heuristic...")
        while time.time() - start_time < timeout:
            for proc in psutil.process_iter(['name']):
                try:
                    if proc.info['name'] and 'vorce' in proc.info['name'].lower():
                        # Process found, sleep longer to wait for UI rendering
                        time.sleep(3)
                        print("Vorce process detected (heuristic fallback).")
                        return True
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    pass
            time.sleep(1)

    print("Timeout waiting for Vorce window.")
    return False

def kill_process_tree(pid):
    """Kills a process and all its children to prevent orphans."""
    try:
        parent = psutil.Process(pid)
        children = parent.children(recursive=True)
        for child in children:
            child.kill()
        parent.kill()
    except psutil.NoSuchProcess:
        pass
    except Exception as e:
        print(f"Error killing process tree: {e}")
