# Vorce UI Automation Harness

This directory contains the Python-based UI test harness for Vorce, designed for Gemini Computer Use and deterministic smoke tests.

## Invoking the Harness

To run the harness, execute `vorce_master_test.py` from the repository root:

```bash
python scripts/gemini-cli/UI-Test_ComputerUse/vorce_master_test.py
```

Or you can use a specific task:

```bash
python scripts/gemini-cli/UI-Test_ComputerUse/vorce_master_test.py --task "Verify main window launches"
```

## Prerequisites

- Windows OS
- Python 3.10+
- `pip install -r requirements.txt` (see below for packages like `pyautogui`, `pillow`, `google-genai`, `psutil`)
- `GEMINI_API_KEY` environment variable set (if using Gemini Vision loop)
- Vorce must build successfully via `cargo run --release`

## Artifacts

All run artifacts are saved under an ignored `output/` directory in this folder:
- `run_report.json`: Structured pass/fail status and run metadata.
- `launch_log.txt`: Captured stdout/stderr from the Vorce process.
- `failure_screenshot.png`: Screenshot taken if a failure occurs.
