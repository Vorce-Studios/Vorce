import subprocess
import time
import sys
import psutil

def wait_for_vorce():
    print("Waiting for Vorce to start...")
    max_retries = 300 # 300 seconds to allow for cargo build
    for i in range(max_retries):
        for proc in psutil.process_iter(['name', 'cmdline']):
            # Cargo might be running Vorce
            if proc.info['name'] and 'vorce' in proc.info['name'].lower():
                print(f"Found Vorce process: {proc.info['name']}")
                return True
            # Also check if it's the actual built binary running
            if proc.info['cmdline']:
                for cmd in proc.info['cmdline']:
                    if 'Vorce' in cmd and 'cargo' not in cmd:
                        print(f"Found Vorce binary: {cmd}")
                        return True
        if i % 10 == 0:
            print(f"Still waiting... ({i}/{max_retries})")
        time.sleep(1)
    print(f"Vorce process not found after {max_retries} seconds.")
    return False

if __name__ == "__main__":
    if not wait_for_vorce():
        sys.exit(1)
