import sys
import os

from vorce_master_test import check_environment

def run_tests():
    print("Running basic environment and prototype checks...")
    missing = check_environment()
    if missing:
        print("Missing required environment items:")
        for item in missing:
            print(f" - {item}")

        # We don't want to strictly fail test_vorce if GEMINI_API_KEY is the only thing missing
        # Extract base issues ignoring the API key
        core_missing = [m for m in missing if "GEMINI_API_KEY" not in m and "Windows OS" not in m]

        if not core_missing:
            print("Environment mostly OK. Only OS/API key missing but continuing for tests.")
            return True
        return False

    print("Environment is fully configured.")
    return True

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
