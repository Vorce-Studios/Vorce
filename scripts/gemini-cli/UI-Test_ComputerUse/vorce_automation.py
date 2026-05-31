import sys

from vorce_ui_harness import main as harness_main

def main():
    print("vorce_automation.py now delegates to vorce_ui_harness.py.")
    if len(sys.argv) == 1:
        sys.argv.extend(["--mode", "env-check"])
    return harness_main()

if __name__ == "__main__":
    raise SystemExit(main())
