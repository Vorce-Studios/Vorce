import sys

from vorce_ui_harness import main as harness_main


def main():
    print("wait_for_vorce.py now delegates to vorce_ui_harness.py launch-check.")
    if len(sys.argv) == 1:
        sys.argv.extend(["--mode", "launch-check"])
    return harness_main()


if __name__ == "__main__":
    raise SystemExit(main())
